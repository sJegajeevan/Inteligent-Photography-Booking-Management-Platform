"""Per-attempt Gemini transport deadlines and cleanup, with no live calls."""
import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from google.genai import errors
from pydantic import ValidationError

from app.config import Settings
from app.llm import AiUnavailable, GeminiService
from app.matching_contracts import StudioRanking
from app.package_contracts import PackageRanking


def configured(**changes):
    return Settings(_env_file=None, gemini_api_key='test-only-dummy-key',
                    gemini_model='test-model', **changes)


def provider_error(status):
    cls = errors.ServerError if status >= 500 else errors.ClientError
    return cls(status, {'error': {'code': status, 'message': 'private test-only-dummy-key'}})


def install_provider(monkeypatch, operations):
    events, options, clients = [], [], []
    real_sleep = asyncio.sleep

    async def sleep(delay):
        if delay in (2.25, 4.25):
            events.append(('backoff', delay))
            await real_sleep(0)
        else:
            await real_sleep(delay)

    class Client:
        def __init__(self, index):
            self.index = index
            self.closed = False
            self.models = SimpleNamespace(generate_content=operations[index], get=operations[index])

        async def __aenter__(self):
            events.append(('open', self.index))
            return self

        async def __aexit__(self, *args):
            self.closed = True
            events.append(('close', self.index))

    def factory(**kwargs):
        options.append(kwargs['http_options'])
        client = Client(len(clients))
        clients.append(client)
        return SimpleNamespace(aio=client)

    monkeypatch.setattr('app.llm.random.uniform', lambda low, high: 0.25)
    monkeypatch.setattr('app.llm.genai.Client', factory)
    monkeypatch.setattr('app.llm.asyncio.sleep', sleep)
    return events, options, clients


@pytest.mark.parametrize('failure', [httpx.ConnectError('private'), httpx.RemoteProtocolError('private'),
    httpx.ReadTimeout('private'), TimeoutError('private'), provider_error(503), provider_error(429)])
def test_transient_failure_then_success_uses_fresh_closed_clients(monkeypatch, failure):
    operations = [AsyncMock(side_effect=failure), AsyncMock(return_value=SimpleNamespace(text='OK'))]
    events, options, clients = install_provider(monkeypatch, operations)
    result = asyncio.run(GeminiService(configured(ai_timeout_seconds=30)).generate_text('test'))
    assert result == 'OK'
    assert events == [('open', 0), ('close', 0), ('backoff', 2.25), ('open', 1), ('close', 1)]
    assert all(c.closed for c in clients)
    assert all(o.timeout == 30000 and o.retry_options.attempts == 1 for o in options)
    assert [op.await_count for op in operations] == [1, 1]


def test_real_attempt_timeout_then_second_success_has_fresh_deadline(monkeypatch):
    async def slow(**kwargs):
        await asyncio.sleep(1)

    async def succeeds(**kwargs):
        await asyncio.sleep(0.025)
        return SimpleNamespace(text='OK')

    operations = [AsyncMock(side_effect=slow), AsyncMock(side_effect=succeeds)]
    events, options, clients = install_provider(monkeypatch, operations)
    assert asyncio.run(GeminiService(configured(ai_timeout_seconds=0.1)).generate_text('test')) == 'OK'
    assert events == [('open', 0), ('close', 0), ('backoff', 2.25), ('open', 1), ('close', 1)]
    assert all(c.closed for c in clients)
    assert [o.timeout for o in options] == [100, 100]
    assert [op.await_count for op in operations] == [1, 1]


@pytest.mark.parametrize('attempts', [1, 2, 3])
@pytest.mark.parametrize('failure,code', [(httpx.ConnectError('private'), 'provider_unavailable'),
    (provider_error(503), 'provider_unavailable'), (httpx.ReadTimeout('private'), 'timeout')])
def test_exhaustion_is_bounded_and_sanitized(monkeypatch, attempts, failure, code):
    operations = [AsyncMock(side_effect=failure) for _ in range(attempts)]
    events, _, clients = install_provider(monkeypatch, operations)
    with pytest.raises(AiUnavailable) as caught:
        asyncio.run(GeminiService(configured(ai_max_attempts=attempts)).generate_text('test'))
    assert caught.value.code == code
    assert str(caught.value) == code
    assert len(clients) == attempts
    assert all(c.closed for c in clients)
    assert all(op.await_count == 1 for op in operations)
    assert [v for event, v in events if event == 'backoff'] == [2.25, 4.25][:attempts-1]


def test_two_deadlines_each_get_full_attempt_budget(monkeypatch):
    elapsed = []
    async def slow(**kwargs):
        loop = asyncio.get_running_loop()
        start = loop.time()
        try:
            await asyncio.sleep(1)
        finally:
            elapsed.append(loop.time() - start)
    operations = [AsyncMock(side_effect=slow), AsyncMock(side_effect=slow)]
    _, _, clients = install_provider(monkeypatch, operations)
    with pytest.raises(AiUnavailable, match='timeout'):
        asyncio.run(GeminiService(configured(ai_timeout_seconds=0.1)).generate_text('test'))
    assert len(elapsed) == 2
    assert all(duration >= 0.09 for duration in elapsed)
    assert all(c.closed for c in clients)


@pytest.mark.parametrize('status', [400, 401, 403, 404, 422])
def test_nonretryable_provider_errors_fail_once_and_close(monkeypatch, status):
    operation = AsyncMock(side_effect=provider_error(status))
    events, _, clients = install_provider(monkeypatch, [operation])
    with pytest.raises(AiUnavailable, match='provider_unavailable'):
        asyncio.run(GeminiService(configured()).generate_text('test'))
    assert operation.await_count == 1
    assert events == [('open', 0), ('close', 0)]
    assert clients[0].closed


@pytest.mark.parametrize('failure', [ValueError('invalid schema'),
    ValidationError.from_exception_data('Schema', [{'type': 'missing', 'loc': ('required',), 'input': {}}])])
def test_sdk_schema_validation_failure_is_not_retried(monkeypatch, failure):
    operation = AsyncMock(side_effect=failure)
    events, _, clients = install_provider(monkeypatch, [operation])
    with pytest.raises(AiUnavailable, match='provider_unavailable'):
        asyncio.run(GeminiService(configured()).rank_studios('test'))
    assert operation.await_count == 1
    assert events == [('open', 0), ('close', 0)]
    assert clients[0].closed


@pytest.mark.parametrize('method,schema', [('rank_studios', StudioRanking), ('rank_packages', PackageRanking)])
@pytest.mark.parametrize('text', ['', 'not json', '{}'])
def test_invalid_model_output_does_not_trigger_transport_retry(monkeypatch, method, schema, text):
    operation = AsyncMock(return_value=SimpleNamespace(text=text))
    events, _, clients = install_provider(monkeypatch, [operation])
    service = GeminiService(configured())
    if not text:
        with pytest.raises(AiUnavailable, match='malformed_structured_output'):
            asyncio.run(getattr(service, method)('test'))
    else:
        raw = asyncio.run(getattr(service, method)('test'))
        with pytest.raises(ValidationError):
            schema.model_validate_json(raw)
    assert operation.await_count == 1
    assert events == [('open', 0), ('close', 0)]
    assert clients[0].closed


def test_missing_configuration_never_creates_client(monkeypatch):
    _, _, clients = install_provider(monkeypatch, [])
    with pytest.raises(AiUnavailable, match='not_configured'):
        asyncio.run(GeminiService(Settings(_env_file=None)).generate_text('test'))
    assert clients == []


def test_external_cancellation_closes_client_without_retry(monkeypatch):
    async def run():
        entered = asyncio.Event()
        async def operation(**kwargs):
            entered.set()
            await asyncio.sleep(10)
        op = AsyncMock(side_effect=operation)
        events, _, clients = install_provider(monkeypatch, [op])
        task = asyncio.create_task(GeminiService(configured()).generate_text('test'))
        await entered.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert op.await_count == 1
        assert events == [('open', 0), ('close', 0)]
        assert clients[0].closed
    asyncio.run(run())


@pytest.mark.parametrize('jitter', [0.0, 0.5])
def test_backoff_grows_with_bounded_jitter_and_cap(monkeypatch, jitter):
    from app.llm import _retry_delay
    def uniform(low, high):
        assert (low, high) == (0.0, 0.5)
        return jitter
    monkeypatch.setattr('app.llm.random.uniform', uniform)
    assert _retry_delay(0) == 2.0 + jitter
    assert _retry_delay(1) == 4.0 + jitter
    assert _retry_delay(2) == 8.0
    assert _retry_delay(20) == 8.0


@pytest.mark.parametrize('status', [429, 500, 502, 503, 504])
def test_provider_retry_uses_logged_backoff_budget(monkeypatch, status):
    operations = [AsyncMock(side_effect=provider_error(status)), AsyncMock(return_value=SimpleNamespace(text='OK'))]
    events, _, _ = install_provider(monkeypatch, operations)
    assert asyncio.run(GeminiService(configured()).rank_packages('test')) == 'OK'
    assert [delay for kind, delay in events if kind == 'backoff'] == [2.25]
