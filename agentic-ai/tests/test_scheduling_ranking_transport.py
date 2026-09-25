"""Real SDK serialization and existing retries over mocked HTTP only."""
import asyncio
import json

import httpx
import pytest
from google import genai

from app.config import Settings
from app.llm import GeminiService
from app.scheduling import SchedulingAgent, SchedulingFailure
from app.scheduling_contracts import SchedulingRanking
from app.scheduling_discovery import SchedulingDiscoveryTool
from test_scheduling import packages, studios, ranking
from test_scheduling_discovery import payload, requirements


@pytest.mark.parametrize("scenario,expected,attempts", [
    ("valid", None, 1), ("503_then_success", None, 2), ("503", "gemini_unavailable", 2),
    ("400", "gemini_unavailable", 1), ("timeout", "gemini_timeout", 2),
    ("extra", "invalid_gemini_output", 1), ("empty", "invalid_gemini_output", 1),
    ("not_configured", "gemini_not_configured", 0),
])
def test_sdk_schema_and_unchanged_retry_transport(monkeypatch, scenario, expected, attempts):
    real_client = genai.Client
    seen = []
    async def run():
        async def provider(request):
            body = json.loads(request.content)
            config = body["generationConfig"]
            seen.append(config)
            assert config["responseMimeType"] == "application/json"
            assert config["responseJsonSchema"] == SchedulingRanking.model_json_schema()
            assert config["responseJsonSchema"]["additionalProperties"] is False
            assert config["responseJsonSchema"]["$defs"]["SlotMatch"]["additionalProperties"] is False
            assert "responseSchema" not in config and "tools" not in body
            if scenario == "timeout":
                await asyncio.sleep(1)
            if scenario in {"503", "400"} or (scenario == "503_then_success" and len(seen) == 1):
                status = 400 if scenario == "400" else 503
                return httpx.Response(status, json={"error": {"code": status, "message": "PRIVATE dummy-key provider detail", "status": "UNAVAILABLE"}})
            text = "" if scenario == "empty" else ranking(date="2026-12-01") if scenario == "extra" else ranking()
            return httpx.Response(200, json={"candidates": [{"content": {"role": "model", "parts": [{"text": text}]}, "finishReason": "STOP"}]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(provider)) as http:
            clients = []
            def factory(**kwargs):
                assert kwargs["http_options"].retry_options.attempts == 1
                kwargs["http_options"].httpx_async_client = http
                client = real_client(**kwargs)
                clients.append(client)
                return client
            monkeypatch.setattr("app.llm.genai.Client", factory)
            settings = Settings(_env_file=None, gemini_api_key="" if scenario == "not_configured" else "dummy-key",
                gemini_model="test-model", ai_max_attempts=2, ai_timeout_seconds=0.1 if scenario == "timeout" else 5)
            discovery = SchedulingDiscoveryTool(settings, transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload())))
            try:
                agent = SchedulingAgent(discovery, GeminiService(settings))
                if expected:
                    with pytest.raises(SchedulingFailure) as error:
                        await agent.schedule(requirements(), studios(), packages())
                    assert error.value.code == expected and str(error.value) == expected
                else:
                    result = await agent.schedule(requirements(), studios(), packages())
                    assert len(result.rankedSlots) == 1
            finally:
                for client in clients:
                    client.close()
        assert len(seen) == attempts
    asyncio.run(run())
