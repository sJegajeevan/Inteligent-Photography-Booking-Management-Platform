"""Exercise the real async Google SDK without contacting Gemini."""

import asyncio

import httpx
import pytest
from google import genai

from app.config import Settings
from app.main import create_app


@pytest.mark.parametrize("delayed", [False, True], ids=["metadata-success", "deadline"])
def test_ai_health_real_async_sdk(monkeypatch, delayed):
    real_client = genai.Client
    requests = []

    async def run():
        async def metadata(request):
            requests.append(request.url.path)
            if delayed:
                await asyncio.sleep(1)
            return httpx.Response(200, json={"name": "models/test-model"})

        async with httpx.AsyncClient(transport=httpx.MockTransport(metadata)) as provider:
            def client_factory(**kwargs):
                kwargs["http_options"].httpx_async_client = provider
                client = real_client(**kwargs)
                clients.append(client)
                return client

            clients = []
            monkeypatch.setattr("app.llm.genai.Client", client_factory)
            settings = Settings(
                _env_file=None,
                gemini_api_key="test-only-dummy-key",
                gemini_model="test-model",
                ai_timeout_seconds=0.25 if delayed else 5,
            )
            app = create_app(settings)
            try:
                async with httpx.AsyncClient(
                    transport=httpx.ASGITransport(app=app), base_url="http://test"
                ) as api:
                    response = await api.get("/health/ai")
                    assert response.status_code == (503 if delayed else 200)
                    if delayed:
                        assert response.json() == {"status": "unavailable", "code": "timeout"}
                    else:
                        assert response.json() == {
                            "status": "ok", "provider": "gemini", "check": "model_metadata"
                        }
                    assert "test-only-dummy-key" not in response.text
                    assert (await api.get("/health")).json()["status"] == "ok"
            finally:
                for client in clients:
                    client.close()

        assert requests == ["/v1beta/models/test-model"] * (2 if delayed else 1)

    asyncio.run(run())
