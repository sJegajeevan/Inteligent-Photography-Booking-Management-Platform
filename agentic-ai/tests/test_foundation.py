import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.llm import AiUnavailable, GeminiService
from app.main import create_app
from app.workflow import WorkflowStatus, build_workflow


def configured(**kwargs):
    return Settings(_env_file=None, gemini_api_key="test-only-dummy-key",
                    gemini_model="test-model", **kwargs)


def fake_provider(monkeypatch, operation):
    class Client:
        async def __aenter__(self):
            return SimpleNamespace(models=SimpleNamespace(get=operation, generate_content=operation))

        async def __aexit__(self, *args):
            return False

    factory_calls = []

    def factory(**kwargs):
        factory_calls.append(kwargs)
        return SimpleNamespace(aio=Client())

    monkeypatch.setattr("app.llm.genai.Client", factory)
    return factory_calls


def test_missing_configuration_is_allowed():
    assert not Settings(_env_file=None).ai_configured


def test_environment_configuration_and_secret_redaction(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test-only-dummy-key")
    monkeypatch.setenv("GEMINI_MODEL", " test-model ")
    monkeypatch.setenv("ASPNET_API_BASE_URL", "https://backend.example.test")
    settings = Settings(_env_file=None)
    assert settings.ai_configured
    assert settings.gemini_model == "test-model"
    assert str(settings.aspnet_api_base_url) == "https://backend.example.test/"
    assert "test-only-dummy-key" not in repr(settings)


@pytest.mark.parametrize("overrides", [
    {"ai_timeout_seconds": 0}, {"ai_max_attempts": 4},
    {"aspnet_api_base_url": "postgresql://localhost/database"},
])
def test_invalid_configuration(overrides):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **overrides)


def test_health_without_gemini(monkeypatch):
    app = create_app(Settings(_env_file=None))
    probe = AsyncMock(side_effect=AssertionError("Liveness must not call Gemini"))
    monkeypatch.setattr(app.state.llm, "check_connectivity", probe)
    with TestClient(app) as client:
        assert client.get("/health").json()["status"] == "ok"
    probe.assert_not_called()


def test_ai_health_unconfigured():
    with TestClient(create_app(Settings(_env_file=None))) as client:
        response = client.get("/health/ai")
    assert response.status_code == 503
    assert response.json()["code"] == "not_configured"


def test_ai_health_metadata_success(monkeypatch):
    operation = AsyncMock(return_value=SimpleNamespace(name="test-model"))
    calls = fake_provider(monkeypatch, operation)
    with TestClient(create_app(configured())) as client:
        response = client.get("/health/ai")
    assert response.status_code == 200
    assert response.json()["check"] == "model_metadata"
    operation.assert_awaited_once_with(model="test-model")
    assert calls[0]["http_options"].retry_options.attempts == 1


def test_provider_error_is_sanitized(monkeypatch):
    operation = AsyncMock(side_effect=RuntimeError("private provider error test-only-dummy-key"))
    fake_provider(monkeypatch, operation)
    with TestClient(create_app(configured())) as client:
        response = client.get("/health/ai")
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable", "code": "provider_unavailable"}
    assert "dummy-key" not in response.text
    assert operation.await_count == 1


def test_transient_failure_retries(monkeypatch):
    operation = AsyncMock(side_effect=[httpx.ConnectError("offline"), SimpleNamespace()])
    fake_provider(monkeypatch, operation)
    asyncio.run(GeminiService(configured()).check_connectivity())
    assert operation.await_count == 2


def test_retry_budget_is_bounded(monkeypatch):
    operation = AsyncMock(side_effect=httpx.ConnectError("offline"))
    fake_provider(monkeypatch, operation)
    with pytest.raises(AiUnavailable, match="provider_unavailable"):
        asyncio.run(GeminiService(configured()).check_connectivity())
    assert operation.await_count == 2


def test_exhausted_attempt_timeouts(monkeypatch):
    async def slow(**kwargs):
        await asyncio.sleep(1)

    fake_provider(monkeypatch, slow)
    with TestClient(create_app(configured(ai_timeout_seconds=0.01))) as client:
        response = client.get("/health/ai")
    assert response.status_code == 503
    assert response.json()["code"] == "timeout"


def test_reusable_generation_boundary(monkeypatch):
    operation = AsyncMock(return_value=SimpleNamespace(text="mock result"))
    fake_provider(monkeypatch, operation)
    assert asyncio.run(GeminiService(configured()).generate_text("mock prompt")) == "mock result"


def test_graph_contains_only_phase41_execution_edges():
    graph = build_workflow().get_graph()
    assert {"Submitted", "StudioMatching", "PackageRecommendation", "Failed"} <= set(graph.nodes)
    edges = {(edge.source, edge.target) for edge in graph.edges}
    for source, target in zip(
        ["Submitted", "StudioMatching", "PackageRecommendation"],
        ["StudioMatching", "PackageRecommendation", "__end__"],
    ):
        assert (source, target) in edges
    assert not any(target in {"Approved", "Rejected"} for _, target in edges)


def test_graph_fails_closed_without_agents():
    result = asyncio.run(build_workflow().ainvoke({}))
    assert result["status"] == WorkflowStatus.FAILED
    assert result["error_code"] == "matching_agent_not_configured"
    assert result["blocked_stage"] == "StudioMatching"


def test_production_graph_includes_scheduling_agent_and_validation_boundary():
    graph = create_app(Settings(_env_file=None)).state.workflow.get_graph()
    edges = {(edge.source, edge.target) for edge in graph.edges}
    assert ("PackageRecommendation", "Scheduling") in edges
    assert ("PackageRecommendation", "Failed") in edges
    assert ("Scheduling", "Validation") in edges
    assert ("Scheduling", "Failed") in edges
    assert ("Validation", "__end__") in edges
    assert "AwaitingApproval" in graph.nodes
    assert "Approved" not in graph.nodes and "Rejected" not in graph.nodes
