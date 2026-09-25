"""Attempt diagnostics expose only allow-listed operational fields."""
import asyncio
import logging
import re
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from google.genai import errors

from app.llm import AiUnavailable, GeminiService
from test_llm_retries import configured, install_provider

PRIVATE = 'test-only-dummy-key SECRET_PROMPT SECRET_RESPONSE Authorization=secret https://private.example/?key=secret'
FORMAT = re.compile(
    r'Gemini attempt [1-3]/[1-3] category=(success|timeout|network_error|provider_error|cancelled|other_error) '
    r'status=(none|[1-5][0-9]{2}) elapsedMs=[0-9]+ retryable=(true|false) willRetry=(true|false) '
    r'agent=(General|Health|StudioMatching|PackageRecommendation|Scheduling|unknown) '
    r'model=[a-zA-Z0-9/._-]+ nextRetryDelayMs=[0-9]+\Z'
)


@pytest.fixture
def attempt_logs(caplog):
    logger = logging.getLogger('snapsync.gemini.attempts')
    logger.addHandler(caplog.handler)
    try:
        yield caplog
        records = [r for r in caplog.records if r.name == logger.name]
        for record in records:
            assert FORMAT.fullmatch(record.getMessage())
            assert record.exc_info is None
            assert record.stack_info is None
        for sensitive in PRIVATE.split():
            assert sensitive not in caplog.text
    finally:
        logger.removeHandler(caplog.handler)


def messages(logs):
    return [r.getMessage() for r in logs.records if r.name == 'snapsync.gemini.attempts']


def http_error(status):
    cls = errors.ServerError if status >= 500 else errors.ClientError
    return cls(status, {'error': {'code': status, 'message': PRIVATE}})


def test_503_retry_and_success_have_only_safe_fields(monkeypatch, attempt_logs):
    operations = [AsyncMock(side_effect=http_error(503)), AsyncMock(return_value=SimpleNamespace(text=PRIVATE))]
    events, _, clients = install_provider(monkeypatch, operations)
    assert asyncio.run(GeminiService(configured()).generate_text(PRIVATE)) == PRIVATE
    logs = messages(attempt_logs)
    assert len(logs) == 2
    assert 'attempt 1/2 category=provider_error status=503' in logs[0]
    assert logs[0].endswith('retryable=true willRetry=true agent=General model=unrecognized nextRetryDelayMs=2250')
    assert 'attempt 2/2 category=success status=none' in logs[1]
    assert logs[1].endswith('retryable=false willRetry=false agent=General model=unrecognized nextRetryDelayMs=0')
    assert all(c.closed for c in clients)
    assert events == [('open', 0), ('close', 0), ('backoff', 2.25), ('open', 1), ('close', 1)]


def test_exhausted_provider_error_logs_no_further_retry(monkeypatch, attempt_logs):
    operations = [AsyncMock(side_effect=http_error(503)) for _ in range(2)]
    install_provider(monkeypatch, operations)
    with pytest.raises(AiUnavailable, match='provider_unavailable'):
        asyncio.run(GeminiService(configured()).generate_text(PRIVATE))
    logs = messages(attempt_logs)
    assert len(logs) == 2
    assert 'status=503' in logs[1]
    assert logs[1].endswith('retryable=true willRetry=false agent=General model=unrecognized nextRetryDelayMs=0')
    assert [op.await_count for op in operations] == [1, 1]


@pytest.mark.parametrize('failure,category,status', [
    (httpx.ReadTimeout(PRIVATE), 'timeout', 'none'),
    (httpx.RemoteProtocolError(PRIVATE), 'network_error', 'none'),
    (http_error(504), 'provider_error', '504'),
])
def test_transport_categories_exclude_exception_details(monkeypatch, attempt_logs, failure, category, status):
    install_provider(monkeypatch, [AsyncMock(side_effect=failure)])
    with pytest.raises(AiUnavailable) as caught:
        asyncio.run(GeminiService(configured(ai_max_attempts=1)).generate_text(PRIVATE))
    assert caught.value.code == ('timeout' if category == 'timeout' else 'provider_unavailable')
    logs = messages(attempt_logs)
    assert len(logs) == 1
    assert f'category={category} status={status}' in logs[0]
    assert logs[0].endswith('retryable=true willRetry=false agent=General model=unrecognized nextRetryDelayMs=0')


@pytest.mark.parametrize('failure,category,status', [
    (http_error(401), 'provider_error', '401'),
    (http_error(400), 'provider_error', '400'),
    (ValueError(PRIVATE), 'other_error', 'none'),
])
def test_nonretryable_failures_log_once(monkeypatch, attempt_logs, failure, category, status):
    operation = AsyncMock(side_effect=failure)
    install_provider(monkeypatch, [operation])
    with pytest.raises(AiUnavailable, match='provider_unavailable'):
        asyncio.run(GeminiService(configured()).generate_text(PRIVATE))
    logs = messages(attempt_logs)
    assert len(logs) == 1
    assert f'category={category} status={status}' in logs[0]
    assert logs[0].endswith('retryable=false willRetry=false agent=General model=unrecognized nextRetryDelayMs=0')
    assert operation.await_count == 1


def test_application_timeout_logged_per_attempt(monkeypatch, attempt_logs):
    async def slow(**kwargs):
        await asyncio.sleep(1)
    operations = [AsyncMock(side_effect=slow), AsyncMock(return_value=SimpleNamespace(text=PRIVATE))]
    install_provider(monkeypatch, operations)
    assert asyncio.run(GeminiService(configured(ai_timeout_seconds=0.01)).generate_text(PRIVATE)) == PRIVATE
    logs = messages(attempt_logs)
    assert len(logs) == 2
    assert 'category=timeout' in logs[0]
    assert 'willRetry=true' in logs[0]
    assert 'category=success' in logs[1]


def test_cancellation_logged_without_retry(monkeypatch, attempt_logs):
    async def run():
        started = asyncio.Event()
        async def slow(**kwargs):
            started.set()
            await asyncio.sleep(10)
        install_provider(monkeypatch, [AsyncMock(side_effect=slow)])
        task = asyncio.create_task(GeminiService(configured()).generate_text(PRIVATE))
        await started.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    asyncio.run(run())
    logs = messages(attempt_logs)
    assert len(logs) == 1
    assert 'category=cancelled status=none' in logs[0]
    assert logs[0].endswith('retryable=false willRetry=false agent=General model=unrecognized nextRetryDelayMs=0')


def test_diagnostics_use_dedicated_console_handler_not_sdk_logging():
    logger = logging.getLogger('snapsync.gemini.attempts')
    assert logger.level == logging.INFO
    assert logger.propagate is False
    assert any(type(handler) is logging.StreamHandler for handler in logger.handlers)


@pytest.mark.parametrize('method,agent', [('rank_studios', 'StudioMatching'),
    ('rank_packages', 'PackageRecommendation'), ('rank_slots', 'Scheduling'), ('check_connectivity', 'Health')])
def test_agent_and_model_are_identified_without_payload(monkeypatch, attempt_logs, method, agent):
    from app.config import Settings
    install_provider(monkeypatch, [AsyncMock(return_value=SimpleNamespace(text=PRIVATE))])
    service = GeminiService(Settings(_env_file=None, gemini_api_key='test-only-dummy-key', gemini_model='gemini-3.6-flash'))
    operation = getattr(service, method)
    asyncio.run(operation() if method == 'check_connectivity' else operation(PRIVATE))
    assert f'agent={agent} model=gemini-3.6-flash nextRetryDelayMs=0' in messages(attempt_logs)[0]


def test_untrusted_diagnostic_labels_are_redacted(monkeypatch, attempt_logs):
    from app.config import Settings
    install_provider(monkeypatch, [AsyncMock(return_value=SimpleNamespace(text=PRIVATE))])
    service = GeminiService(Settings(_env_file=None, gemini_api_key='test-only-dummy-key', gemini_model=PRIVATE))
    asyncio.run(service._call(lambda client: client.models.generate_content(), agent=PRIVATE))
    assert 'agent=unknown model=unrecognized nextRetryDelayMs=0' in messages(attempt_logs)[0]
