"""Offline ASGI boundary checks, including the existing graph and deterministic validator."""
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import httpx
import pytest

from app.config import Settings
from app.internal_execution import ExecutionCompletion, REQUEST_LIMIT, RESPONSE_LIMIT
from app.main import create_app
from app.validation import ValidationAgent
from app.workflow import build_workflow
from test_validation import state
from test_validation_discovery import payload, tool

TOKEN = "offline-internal-service-test-token-32-characters"
WORKFLOW, EXECUTION = str(uuid4()), str(uuid4())


def setup(*, result=None, exception=None, classification="Pass", timeout=120, token=TOKEN):
    app = create_app(Settings(_env_file=None, internal_workflow_token=token, workflow_timeout_seconds=timeout))
    values = state()
    calls = []
    def backend(request):
        calls.append(request)
        return httpx.Response(200, json=payload(classification))
    agents = [SimpleNamespace(match=AsyncMock(return_value=values["studios"])),
              SimpleNamespace(recommend=AsyncMock(return_value=values["packages"])),
              SimpleNamespace(schedule=AsyncMock(return_value=values["scheduling"]))]
    app.state.workflow = build_workflow(*agents, ValidationAgent(tool(backend)))
    if result is not None or exception is not None:
        app.state.workflow = SimpleNamespace(ainvoke=AsyncMock(return_value=result, side_effect=exception))
    body = dict(executionId=EXECUTION, requirements=values["requirements"].model_dump(mode="json"))
    return app, body, calls, agents


def send(app, body, token=TOKEN, workflow=WORKFLOW):
    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://internal") as client:
            headers = {"X-Internal-Token": token} if token is not None else {}
            return await client.post(f"/internal/ai-workflows/{workflow}/run", headers=headers,
                                     content=body if isinstance(body, (str, bytes)) else json.dumps(body))
    return asyncio.run(run())


@pytest.mark.parametrize("token", [None, "wrong", "", "Bearer customer-jwt"])
def test_authentication_before_body_or_graph(token):
    app, _, calls, _ = setup(result={})
    response = send(app, "PRIVATE malformed", token)
    assert response.status_code == 401 and response.json() == {"errorCode": "unauthorized"}
    app.state.workflow.ainvoke.assert_not_awaited()
    assert not calls


def test_unconfigured_service_fails_closed():
    app, body, _, _ = setup(token="", result={})
    assert send(app, body).status_code == 401
    app.state.workflow.ainvoke.assert_not_awaited()


def test_real_graph_pass_is_narrow_correlated_and_has_no_write_tools():
    app, body, calls, agents = setup()
    response = send(app, body)
    assert response.status_code == 200
    result = ExecutionCompletion.model_validate_json(response.content)
    assert result.status == "AwaitingApproval" and result.evidence.classification == "Pass"
    assert str(result.workflowId) == WORKFLOW and str(result.executionId) == EXECUTION
    assert result.requirements.model_dump(mode="json") == body["requirements"]
    assert len(result.schedulingEvidence.candidates) == 1
    assert result.schedulingEvidence.candidates[0].date == result.evidence.current.selection.date
    assert len(response.content) <= RESPONSE_LIMIT
    assert set(response.json()) == {"workflowId", "executionId", "status", "requirements", "evidence", "schedulingEvidence", "errorCode"}
    for agent, method in zip(agents, ("match", "recommend", "schedule")):
        getattr(agent, method).assert_awaited_once()
    assert len(calls) == 1 and calls[0].url.path.endswith("/validate-recommendation")
    assert TOKEN not in response.text and "gemini" not in response.text.lower()
    assert not any(word in response.json() for word in ("proposal", "proposalVersion", "reviewer", "approval", "booking", "events"))


@pytest.mark.parametrize("field", ["customerId", "proposalVersion", "reviewer", "decision", "backendUrl", "tools", "workflowId"])
def test_request_rejects_extra_fields(field):
    app, body, _, _ = setup(result={})
    body[field] = "PRIVATE"
    response = send(app, body)
    assert response.status_code == 400 and "PRIVATE" not in response.text
    app.state.workflow.ainvoke.assert_not_awaited()


@pytest.mark.parametrize("change", [lambda b: b["requirements"].update(customerId=7),
    lambda b: b["requirements"].update(notes="PRIVATE prompt"),
    lambda b: b.update(executionId="00000000-0000-0000-0000-000000000000"),
    lambda b: b["requirements"].update(requestedServices=["x"] * 21),
    lambda b: b["requirements"].update(maximumBudget=True)])
def test_invalid_nested_input_is_sanitized(change):
    app, body, _, _ = setup(result={})
    change(body)
    response = send(app, body)
    assert response.status_code == 400 and response.json() == {"errorCode": "invalid_request"}
    app.state.workflow.ainvoke.assert_not_awaited()


@pytest.mark.parametrize("body,status", [("PRIVATE", 400), ("null", 400), ("{}", 400),
    ('{"executionId":"x","executionId":"y"}', 400), ("x" * (REQUEST_LIMIT + 1), 413)])
def test_bounded_body(body, status):
    app, _, _, _ = setup(result={})
    assert send(app, body).status_code == status
    app.state.workflow.ainvoke.assert_not_awaited()


@pytest.mark.parametrize("classification,status", [("Fail", "Failed"), ("RevalidationRequired", "RevalidationRequired")])
def test_real_graph_failure_has_no_publication_evidence(classification, status):
    app, body, calls, _ = setup(classification=classification)
    result = send(app, body).json()
    assert result["status"] == status and result["evidence"] is None and result["schedulingEvidence"] is None
    assert len(calls) == 1


@pytest.mark.parametrize("state", [{}, {"status": "Approved"}, {"status": "AwaitingApproval"},
    {"status": "AwaitingApproval", "error_code": "PRIVATE"}, {"status": "Validation"}])
def test_malformed_state_fails_closed(state):
    app, body, _, _ = setup(result=state)
    result = send(app, body)
    assert result.json()["status"] == "Failed" and result.json()["errorCode"] == "invalid_execution_response"
    assert "PRIVATE" not in result.text


def test_needs_input_is_preserved_without_raw_events():
    app, body, _, _ = setup(result={"status": "NeedsInput", "events": [{"prompt": "PRIVATE"}]})
    result = send(app, body)
    assert result.json()["status"] == "NeedsInput" and "PRIVATE" not in result.text


def test_provider_exception_is_never_exposed_or_logged(caplog):
    app, body, _, _ = setup(exception=RuntimeError("PRIVATE GEMINI KEY " + TOKEN))
    response = send(app, body)
    assert response.json()["status"] == "Failed"
    assert "PRIVATE" not in response.text + caplog.text and TOKEN not in response.text + caplog.text


def test_execution_timeout_is_bounded_and_cancels_graph():
    app, body, _, _ = setup(timeout=0.01)
    cancelled = []
    async def slow(*args, **kwargs):
        try:
            await asyncio.sleep(10)
        finally:
            cancelled.append(True)
    app.state.workflow = SimpleNamespace(ainvoke=slow)
    response = send(app, body)
    assert response.json()["errorCode"] == "execution_timeout" and cancelled == [True]


def test_transient_location_is_only_invocation_context():
    app, body, _, _ = setup(result={"status": "Failed"})
    body["nearby"] = {"latitude": 9.66, "longitude": 80.01, "radiusKm": 10}
    response = send(app, body)
    context = app.state.workflow.ainvoke.call_args.kwargs["context"]
    assert context.request.nearby.latitude == 9.66
    assert "latitude" not in response.text and "nearby" not in response.text


@pytest.mark.parametrize("mode", ["oversized", "altered_requirements", "missing_schedule", "raw_trace"])
def test_success_state_is_validated_and_bounded(mode):
    app, body, _, _ = setup()
    graph = app.state.workflow
    async def invoke(*args, **kwargs):
        result = await graph.ainvoke(*args, **kwargs)
        if mode == "oversized":
            result["validation"]["current"]["pricing"]["packageName"] = "x" * RESPONSE_LIMIT
        elif mode == "altered_requirements":
            result["validation_requirements"]["maximumBudget"] = "1"
        elif mode == "missing_schedule":
            result["scheduling"]["backendEvidence"] = []
        else:
            result["events"] = [{"prompt": "PRIVATE", "authorization": TOKEN}]
            result["raw_model_response"] = "PRIVATE"
        return result
    app.state.workflow = SimpleNamespace(ainvoke=invoke)
    response = send(app, body)
    assert response.json()["status"] == ("AwaitingApproval" if mode == "raw_trace" else "Failed")
    assert len(response.content) <= RESPONSE_LIMIT and "PRIVATE" not in response.text and TOKEN not in response.text


def test_shared_python_dotnet_fixture_remains_a_valid_completion():
    from pathlib import Path
    fixture = Path(__file__).resolve().parents[2] / "backend/tests/Phase1Checks/Fixtures/python-completion.json"
    result = ExecutionCompletion.model_validate_json(fixture.read_bytes())
    assert result.status == "AwaitingApproval" and result.evidence.classification == "Pass"
