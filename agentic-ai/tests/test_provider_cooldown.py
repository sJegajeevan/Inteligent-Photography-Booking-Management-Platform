"""Offline provider metadata, deadlines, shared cooldown and graph failure checks."""
import asyncio
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from google.genai import errors
from pydantic import ValidationError

from app.config import Settings
from app.llm import AiUnavailable, GeminiService, _provider_retry_delay, _retry_delay
from app.workflow import build_workflow
from test_llm_retries import configured, install_provider


def error(status=429, header=None, delay=None):
    response = httpx.Response(status, headers={} if header is None else {'Retry-After': header})
    body = {'error': {'message': 'PRIVATE API_KEY customer data', 'details': [
        {'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': delay}]}}
    return errors.APIError(status, body, response)


@pytest.mark.parametrize('header,delay,expected', [('7', None, 7), (None, '9.5s', 9.5),
    ('5', '12s', 12), ('15', '2s', 15), ('0', None, 0), ('garbage', 'NaNs', 0),
    ('-1', '-2s', 0), ('inf', 'infs', 0), (None, None, 0)])
def test_structured_delay_only(header, delay, expected):
    assert _provider_retry_delay(error(header=header, delay=delay)) == expected


def test_retry_after_http_date():
    future = format_datetime(datetime.now(timezone.utc) + timedelta(seconds=12), usegmt=True)
    assert 10 < _provider_retry_delay(error(header=future)) <= 12
    past = format_datetime(datetime.now(timezone.utc) - timedelta(seconds=12), usegmt=True)
    assert _provider_retry_delay(error(header=past)) == 0


@pytest.mark.parametrize('status', [429, 503])
@pytest.mark.parametrize('metadata', [{'header': '7'}, {'delay': '9.5s'}])
def test_provider_wait_is_respected_without_body_logging(monkeypatch, caplog, status, metadata):
    operations = [AsyncMock(side_effect=error(status, **metadata)), AsyncMock(return_value=SimpleNamespace(text='OK'))]
    _, _, clients = install_provider(monkeypatch, operations)
    sleeps = []
    async def sleep(delay):
        sleeps.append(delay)
    monkeypatch.setattr('app.llm.asyncio.sleep', sleep)
    assert asyncio.run(GeminiService(configured()).rank_packages('PRIVATE prompt')) == 'OK'
    assert sleeps == [7 if 'header' in metadata else 9.5]
    assert len(clients) == 2 and all(client.closed for client in clients)
    assert 'PRIVATE' not in caplog.text and 'API_KEY' not in caplog.text


def test_long_provider_wait_fails_without_early_retry_and_logs_truthfully(monkeypatch, caplog):
    import logging
    logger = logging.getLogger('snapsync.gemini.attempts')
    logger.addHandler(caplog.handler)
    try:
        operation = AsyncMock(side_effect=error(header='120'))
        _, _, clients = install_provider(monkeypatch, [operation])
        service = GeminiService(configured())
        sleep = AsyncMock()
        monkeypatch.setattr('app.llm.asyncio.sleep', sleep)
        for _ in range(2):
            with pytest.raises(AiUnavailable, match='provider_unavailable'):
                asyncio.run(service.rank_studios('PRIVATE prompt'))
        assert operation.await_count == len(clients) == 1
        sleep.assert_not_awaited()
        assert 'willRetry=false' in caplog.text and 'nextRetryDelayMs=0' in caplog.text
        assert 'PRIVATE' not in caplog.text and 'API_KEY' not in caplog.text
    finally:
        logger.removeHandler(caplog.handler)


def test_shared_rate_limit_cooldown_paces_next_agent_but_not_success(monkeypatch):
    operations = [AsyncMock(side_effect=error(delay='6s')),
                  AsyncMock(return_value=SimpleNamespace(text='OK')),
                  AsyncMock(return_value=SimpleNamespace(text='OK'))]
    install_provider(monkeypatch, operations)
    clock = [100.0]
    monkeypatch.setattr('app.llm.monotonic', lambda: clock[0])
    sleeps = []
    async def sleep(delay):
        sleeps.append(delay)
        clock[0] += delay
    monkeypatch.setattr('app.llm.asyncio.sleep', sleep)
    service = GeminiService(configured(ai_max_attempts=1))
    async def run():
        with pytest.raises(AiUnavailable):
            await service.rank_studios('test')
        assert await service.rank_packages('test') == 'OK'
        assert await service.rank_slots('test') == 'OK'
    asyncio.run(run())
    assert sleeps == [6]


def test_total_call_budget_cancels_inflight_attempt(monkeypatch):
    async def slow(**kwargs):
        await asyncio.sleep(1)
    operation = AsyncMock(side_effect=slow)
    _, _, clients = install_provider(monkeypatch, [operation])
    with pytest.raises(AiUnavailable, match='timeout'):
        asyncio.run(GeminiService(configured(ai_call_budget_seconds=0.02, ai_timeout_seconds=1)).rank_slots('test'))
    assert operation.await_count == 1 and clients[0].closed


def test_wait_that_cannot_fit_budget_does_not_retry(monkeypatch):
    operation = AsyncMock(side_effect=error(status=503, header='10'))
    install_provider(monkeypatch, [operation])
    sleep = AsyncMock()
    monkeypatch.setattr('app.llm.asyncio.sleep', sleep)
    with pytest.raises(AiUnavailable, match='provider_unavailable'):
        asyncio.run(GeminiService(configured(ai_call_budget_seconds=5)).rank_packages('test'))
    sleep.assert_not_awaited()
    assert operation.await_count == 1


@pytest.mark.parametrize('jitter', [0, 0.5])
def test_429_fallback_is_slower_and_bounded(monkeypatch, jitter):
    monkeypatch.setattr('app.llm.random.uniform', lambda *_: jitter)
    assert _retry_delay(0, 429) == 4 + jitter
    assert _retry_delay(1, 429) == 8
    assert _retry_delay(100, 429) == 8


@pytest.mark.parametrize('budget', [0, -1, 61])
def test_invalid_budget_rejected(budget):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, ai_call_budget_seconds=budget)


@pytest.mark.parametrize('stage', ['StudioMatching', 'PackageRecommendation', 'Scheduling'])
@pytest.mark.parametrize('status', [429, 503])
def test_real_retry_exhaustion_preserves_node_in_internal_workflow(monkeypatch, stage, status):
    from test_internal_execution import setup, send
    from test_validation import state
    operations = [AsyncMock(side_effect=error(status)) for _ in range(2)]
    install_provider(monkeypatch, operations)
    service = GeminiService(configured())
    values = state()
    async def failing(*args):
        await getattr(service, {'StudioMatching': 'rank_studios', 'PackageRecommendation': 'rank_packages',
                               'Scheduling': 'rank_slots'}[stage])('PRIVATE prompt')
        raise AssertionError('Provider failure must not fabricate success')
    studio = SimpleNamespace(match=failing if stage == 'StudioMatching' else AsyncMock(return_value=values['studios']))
    package = SimpleNamespace(recommend=failing if stage == 'PackageRecommendation' else AsyncMock(return_value=values['packages']))
    scheduling = SimpleNamespace(schedule=failing if stage == 'Scheduling' else AsyncMock(return_value=values['scheduling']))
    validation = SimpleNamespace(validate=AsyncMock(side_effect=AssertionError('Must not validate failed ranking')))
    app, body, _, _ = setup()
    app.state.workflow = build_workflow(studio, package, scheduling, validation)
    response = send(app, body).json()
    assert response['status'] == 'Failed'
    assert response['failureStage'] == stage
    assert response['errorCode'] == 'gemini_unavailable'
    assert response['evidence'] is None and response['schedulingEvidence'] is None
    assert 'booking' not in response and 'PRIVATE' not in str(response)
    assert all(op.await_count == 1 for op in operations)
    validation.validate.assert_not_awaited()
