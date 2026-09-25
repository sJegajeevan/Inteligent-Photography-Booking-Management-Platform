import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from google import genai
from pydantic import ValidationError

from app.config import Settings
from app.llm import AiUnavailable, GeminiService
from app.matching_contracts import StudioMatchingInput, StudioRanking
from app.studio_discovery import StudioDiscoveryTool
from app.studio_matching import StudioMatchingAgent
from app.workflow import MatchingContext, build_workflow


STUDIO_ID = "ab123456-1234-4234-8234-123456789012"
REASON = "Lists the requested photography type and a starting price within the maximum budget."
WILDCARD_REASON = "Supports all photography types and lists a starting price within the maximum budget."


def request(**changes):
    requirements = dict(photographyType="Wedding", location="Colombo", maximumBudget=100000,
                        earliestDate="2026-12-01", latestDate="2026-12-02", coverageHours=4,
                        requestedServices=["Photography"])
    requirements.update(changes)
    return StudioMatchingInput(requirements=requirements)


def studio(**changes):
    result = dict(id=STUDIO_ID, studioName="Studio A", location="Colombo",
                  descriptionSummary="Public description", photographyTypes=["Wedding"],
                  startingPrice=50000, distanceKm=None, profileImageUrl=None, coverImageUrl=None)
    result.update(changes)
    return result


def ranking(studio_id=STUDIO_ID, reason=REASON, **changes):
    result = dict(rankedStudios=[dict(studioId=studio_id, explanationSummary=reason)])
    result.update(changes)
    return json.dumps(result)


def execute(handler=None, llm=None, matching_request=None):
    handler = handler or (lambda req: httpx.Response(200, json=[studio()]))
    llm = llm or SimpleNamespace(rank_studios=AsyncMock(return_value=ranking()))
    settings = Settings(_env_file=None)
    agent = StudioMatchingAgent(StudioDiscoveryTool(settings, transport=httpx.MockTransport(handler)), llm)
    return asyncio.run(build_workflow(agent).ainvoke(
        {}, context=MatchingContext(matching_request or request()))), llm


def test_success_and_graph_boundary():
    result, llm = execute()
    assert result["status"] == "PackageRecommendation"
    assert result["error_code"] == "package_agent_not_implemented"
    assert result["blocked_stage"] == "PackageRecommendation"
    assert result["studio_matching"]["rankedStudios"] == json.loads(ranking())["rankedStudios"]
    assert result["events"][0]["success"] is True
    assert result["events"][0]["durationMs"] >= 0
    llm.rank_studios.assert_awaited_once()


@pytest.mark.parametrize("data", [[], [studio(photographyTypes=["Portrait"])], [studio(startingPrice=100001)]])
def test_no_eligible_candidates_skips_gemini(data):
    result, llm = execute(lambda req: httpx.Response(200, json=data))
    assert result["status"] == "Failed"
    assert result["error_code"] == "no_matching_studios"
    assert result["studio_matching"]["rankedStudios"] == []
    llm.rank_studios.assert_not_called()


@pytest.mark.parametrize("types,price,reason,eligible", [
    (["All"], 0, WILDCARD_REASON, True),
    (["all"], 50000, WILDCARD_REASON, True),
    ([" ALL "], 100000, WILDCARD_REASON, True),
    ([" Wedding "], 50000, REASON, True),
    (["Portrait"], 50000, REASON, False),
    (["All"], 100001, WILDCARD_REASON, False),
])
def test_photography_type_wildcard_eligibility(types, price, reason, eligible):
    result, llm = execute(
        lambda req: httpx.Response(200, json=[studio(photographyTypes=types, startingPrice=price)]),
        llm=SimpleNamespace(rank_studios=AsyncMock(return_value=ranking(reason=reason))),
        matching_request=request(photographyType=" Wedding "),
    )
    if eligible:
        assert result["status"] == "PackageRecommendation"
        assert result["studio_matching"]["rankedStudios"] == json.loads(ranking(reason=reason))["rankedStudios"]
        llm.rank_studios.assert_awaited_once()
    else:
        assert result["error_code"] == "no_matching_studios"
        assert result["studio_matching"]["rankedStudios"] == []
        llm.rank_studios.assert_not_called()


@pytest.mark.parametrize("nearby", [None, dict(latitude=6, longitude=79, radiusKm=15)])
def test_wildcard_explanations_do_not_claim_explicit_requested_type(nearby):
    data = request().model_dump()
    data["nearby"] = nearby
    result, llm = execute(
        lambda req: httpx.Response(200, json=[studio(photographyTypes=["All"], distanceKm=4.2)]),
        matching_request=data,
    )
    allowed = json.loads(llm.rank_studios.call_args.args[0])["candidates"][0]["allowedReasons"]
    assert allowed == [WILDCARD_REASON] + ([
        "Supports all photography types and is within the requested search radius."
    ] if nearby else [])
    # The mocked model returns the old explicit-type claim; reject it for All.
    assert result["error_code"] == "unsupported_recommendation_claim"


@pytest.mark.parametrize("failure,code", [
    (httpx.ReadTimeout("private details"), "backend_timeout"),
    (httpx.ConnectError("private details"), "backend_unavailable"),
])
def test_backend_transport_failure(failure, code):
    def handler(req):
        raise failure
    result, llm = execute(handler)
    assert result["error_code"] == code
    assert "private details" not in json.dumps(result)
    llm.rank_studios.assert_not_called()


@pytest.mark.parametrize("status", [301, 302, 401, 404, 500, 503])
def test_backend_status_and_redirect_fail_closed(status):
    calls = []
    def handler(req):
        calls.append(req)
        return httpx.Response(status, headers={"location": "https://untrusted.example/"})
    result, _ = execute(handler)
    assert result["error_code"] == "backend_unavailable"
    assert len(calls) == 1


@pytest.mark.parametrize("data", [
    {}, [studio(id="made-up")], [studio(id="00000000-0000-0000-0000-000000000000")],
    [studio(startingPrice=-1)], [studio(), studio()], [dict(id=STUDIO_ID)],
    [studio(distanceKm=-1)], [studio(unknownField="unexpected")],
])
def test_invalid_backend_response(data):
    result, llm = execute(lambda req: httpx.Response(200, json=data))
    assert result["error_code"] == "invalid_backend_response"
    llm.rank_studios.assert_not_called()


def test_invalid_backend_json_and_size_limit():
    for body in [b"not json", b"x" * 1_000_001]:
        result, _ = execute(lambda req: httpx.Response(200, content=body))
        assert result["error_code"] == "invalid_backend_response"


@pytest.mark.parametrize("code,expected", [("timeout", "gemini_timeout"),
    ("not_configured", "gemini_not_configured"), ("provider_unavailable", "gemini_unavailable")])
def test_gemini_failure(code, expected):
    result, _ = execute(llm=SimpleNamespace(rank_studios=AsyncMock(side_effect=AiUnavailable(code))))
    assert result["error_code"] == expected
    assert result["studio_matching"] is None
    assert result["events"][0]["success"] is False


@pytest.mark.parametrize("raw", ["not json", "{}", '{"rankedStudios": []}',
    ranking(untrusted="extra"), ranking().replace('"explanationSummary"', '"reason"'),
    ranking().replace('"studioId":', '"price": 1, "studioId":'), None])
def test_malformed_structured_response(raw):
    result, _ = execute(llm=SimpleNamespace(rank_studios=AsyncMock(return_value=raw)))
    assert result["error_code"] == "malformed_structured_output"
    assert result["studio_matching"] is None


@pytest.mark.parametrize("studio_id", ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", STUDIO_ID.upper()])
def test_unknown_or_nonexact_id_rejected(studio_id):
    result, _ = execute(llm=SimpleNamespace(rank_studios=AsyncMock(return_value=ranking(studio_id))))
    assert result["error_code"] == "unknown_studio_id"
    assert result["studio_matching"] is None


@pytest.mark.parametrize("reason", ["Available on your preferred date.", "Costs LKR 10.",
    "Only 1 km away.", "Best rated studio.", REASON + " Guaranteed booking.",
    "Lists the requested photography type and is within the requested search radius."])
def test_unsupported_claims_rejected(reason):
    result, _ = execute(llm=SimpleNamespace(rank_studios=AsyncMock(return_value=ranking(reason=reason))))
    assert result["error_code"] == "unsupported_recommendation_claim"


def test_duplicate_model_id_rejected():
    data = json.loads(ranking())
    data["rankedStudios"] *= 2
    result, _ = execute(llm=SimpleNamespace(rank_studios=AsyncMock(return_value=json.dumps(data))))
    assert result["error_code"] == "duplicate_studio_id"


def test_allowlisted_nearby_query_and_transient_gps():
    data = request(notes="PRIVATE CUSTOMER NOTE").model_dump()
    data["nearby"] = {"latitude": 6.9271, "longitude": 79.8612, "radiusKm": 15}
    req = StudioMatchingInput.model_validate(data)
    def handler(http_request):
        assert http_request.method == "GET"
        assert http_request.url.path == "/api/public/studios/nearby"
        assert dict(http_request.url.params) == {
            "location": "Colombo", "latitude": "6.9271", "longitude": "79.8612", "radiusKm": "15.0"}
        return httpx.Response(200, json=[studio(distanceKm=4.2)])
    result, llm = execute(handler, matching_request=req)
    prompt = llm.rank_studios.call_args.args[0]
    assert json.loads(prompt)["candidates"][0]["distanceKm"] == 4.2
    for private in ["6.9271", "79.8612", "PRIVATE CUSTOMER NOTE"]:
        assert private not in prompt
        assert private not in json.dumps(result)


@pytest.mark.parametrize("distance", [None, 16])
def test_nearby_missing_or_outside_radius_rejected(distance):
    req = request().model_dump()
    req["nearby"] = dict(latitude=6, longitude=79, radiusKm=15)
    result, _ = execute(lambda req: httpx.Response(200, json=[studio(distanceKm=distance)]),
                        matching_request=req)
    assert result["error_code"] == "invalid_backend_response"


def test_normal_endpoint_and_no_arbitrary_url():
    def handler(req):
        assert req.method == "GET"
        assert str(req.url) == "http://localhost:5000/api/public/studios?location=Colombo"
        return httpx.Response(200, json=[studio()])
    execute(handler)
    for url in ["http://user:password@localhost", "http://localhost/api", "http://localhost?x=y"]:
        with pytest.raises(ValidationError):
            Settings(_env_file=None, aspnet_api_base_url=url)


@pytest.mark.parametrize("changes", [dict(latestDate="2026-01-01"), dict(minimumBudget=100001),
    dict(preferredStartTime="10:00"), dict(currency="USD"), dict(photographyType="  "),
    dict(requestedServices=[""]), dict(coverageHours=0), dict(latitude=6)])
def test_requirements_contract_validation(changes):
    with pytest.raises(ValidationError):
        request(**changes)


def test_invalid_graph_input_and_stale_result_cleared():
    agent = StudioMatchingAgent(AsyncMock(), AsyncMock())
    result = asyncio.run(build_workflow(agent).ainvoke(
        {"studio_matching": {"rankedStudios": ["stale"]}}, context=MatchingContext({})))
    assert result["error_code"] == "invalid_matching_input"
    assert result["studio_matching"] is None
    agent.discovery.discover.assert_not_called()


def test_total_backend_deadline():
    async def handler(req):
        await asyncio.sleep(1)
        return httpx.Response(200, json=[])
    tool = StudioDiscoveryTool(Settings(_env_file=None, aspnet_timeout_seconds=0.01),
                               transport=httpx.MockTransport(handler))
    result = asyncio.run(build_workflow(StudioMatchingAgent(tool, AsyncMock())).ainvoke(
        {}, context=MatchingContext(request())))
    assert result["error_code"] == "backend_timeout"


def test_gemini_structured_generation_config(monkeypatch):
    operation = AsyncMock(return_value=SimpleNamespace(text=ranking()))
    class Client:
        async def __aenter__(self):
            return SimpleNamespace(models=SimpleNamespace(generate_content=operation))
        async def __aexit__(self, *args):
            pass
    monkeypatch.setattr("app.llm.genai.Client", lambda **kwargs: SimpleNamespace(aio=Client()))
    service = GeminiService(Settings(_env_file=None, gemini_api_key="test-only-dummy-key", gemini_model="test"))
    assert asyncio.run(service.rank_studios("test payload")) == ranking()
    config = operation.call_args.kwargs["config"]
    assert config.response_mime_type == "application/json"
    assert config.response_schema is None
    assert config.response_json_schema == StudioRanking.model_json_schema()
    assert config.tools is None
    assert config.max_output_tokens == 2048


@pytest.mark.parametrize("provider_status,output,expected", [
    (200, ranking(), "package_agent_not_implemented"),
    (200, ranking(untrusted="extra"), "malformed_structured_output"),
    (200, ranking().replace('"studioId":', '"price": 1, "studioId":'), "malformed_structured_output"),
    (400, None, "gemini_unavailable"),
])
def test_ranking_json_schema_wire_transport_and_validation(monkeypatch, provider_status, output, expected):
    real_client = genai.Client
    requests = []

    async def run():
        def provider_response(request):
            body = json.loads(request.content)
            config = body["generationConfig"]
            assert config["responseMimeType"] == "application/json"
            assert "responseSchema" not in config
            assert config["responseJsonSchema"] == StudioRanking.model_json_schema()
            assert config["responseJsonSchema"]["additionalProperties"] is False
            assert config["responseJsonSchema"]["$defs"]["StudioMatch"]["additionalProperties"] is False
            assert "additional_properties" not in request.content.decode()
            requests.append(request.url.path)
            if provider_status == 400:
                return httpx.Response(400, json={"error": {
                    "code": 400, "status": "INVALID_ARGUMENT", "message": "private provider detail"}})
            return httpx.Response(200, json={"candidates": [{
                "content": {"role": "model", "parts": [{"text": output}]}, "finishReason": "STOP"}]})

        async with httpx.AsyncClient(transport=httpx.MockTransport(provider_response)) as provider:
            clients = []

            def client_factory(**kwargs):
                kwargs["http_options"].httpx_async_client = provider
                client = real_client(**kwargs)
                clients.append(client)
                return client

            monkeypatch.setattr("app.llm.genai.Client", client_factory)
            settings = Settings(_env_file=None, gemini_api_key="test-only-dummy-key", gemini_model="test-model")
            tool = StudioDiscoveryTool(settings, transport=httpx.MockTransport(
                lambda req: httpx.Response(200, json=[studio()])))
            try:
                result = await build_workflow(StudioMatchingAgent(tool, GeminiService(settings))).ainvoke(
                    {}, context=MatchingContext(request()))
                assert result["error_code"] == expected
                assert "private provider detail" not in json.dumps(result)
                assert "test-only-dummy-key" not in json.dumps(result)
                if expected != "package_agent_not_implemented":
                    assert result["status"] == "Failed"
                    assert result["studio_matching"] is None
            finally:
                for client in clients:
                    client.close()
        assert len(requests) == 1

    asyncio.run(run())


def test_model_can_rank_only_supplied_candidates_in_its_chosen_order():
    second_id = "bb123456-1234-4234-8234-123456789012"
    raw = json.dumps({"rankedStudios": [
        {"studioId": second_id, "explanationSummary": REASON},
        {"studioId": STUDIO_ID, "explanationSummary": REASON}]})
    result, _ = execute(lambda req: httpx.Response(200, json=[studio(), studio(id=second_id)]),
                        llm=SimpleNamespace(rank_studios=AsyncMock(return_value=raw)))
    assert [item["studioId"] for item in result["studio_matching"]["rankedStudios"]] == [second_id, STUDIO_ID]


def test_graph_emits_only_expected_success_stages():
    tool = StudioDiscoveryTool(Settings(_env_file=None), transport=httpx.MockTransport(
        lambda req: httpx.Response(200, json=[studio()])))
    agent = StudioMatchingAgent(tool, SimpleNamespace(rank_studios=AsyncMock(return_value=ranking())))
    async def run():
        return [list(update)[0] async for update in build_workflow(agent).astream(
            {}, context=MatchingContext(request()), stream_mode="updates")]
    assert asyncio.run(run()) == ["Submitted", "StudioMatching", "PackageRecommendation"]


def test_candidate_prompt_limit_is_disclosed():
    studios = [studio(id=f"ab123456-1234-4234-8234-{i:012d}") for i in range(51)]
    result, llm = execute(lambda req: httpx.Response(200, json=studios),
                        llm=SimpleNamespace(rank_studios=AsyncMock(return_value=ranking(studios[0]["id"]))))
    assert len(json.loads(llm.rank_studios.call_args.args[0])["candidates"]) == 50
    assert any("50" in item for item in result["studio_matching"]["unmetPreferences"])
