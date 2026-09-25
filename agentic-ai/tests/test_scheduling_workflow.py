"""Workflow integration only, with mocked agents and no external calls."""
import asyncio
from datetime import date
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.config import Settings
from app.main import create_app
from app.matching_contracts import StudioMatchingInput
from app.package_recommendation import PackageFailure
from app.scheduling import SchedulingFailure
from app.scheduling_contracts import ProposedSlot, SchedulingOutput
from app.studio_matching import MatchingFailure
from app.workflow import MatchingContext, build_workflow
from test_scheduling import packages, studios, REASON
from test_scheduling_discovery import SID, PID, requirements


def output():
    return SchedulingOutput(rankedSlots=[ProposedSlot(studioId=SID, packageId=PID, date=date(2026, 12, 1),
        startTime="08:00:00.1234567", endTime="12:00:00.1234567", explanationSummary=REASON,
        evidenceIds=["backend-evidence"])], unmetPreferences=["Point-in-time evidence, not a reservation."])


def execute(*, scheduling_error=None, studio_error=None, package_error=None):
    matching = SimpleNamespace(match=AsyncMock(return_value=studios(), side_effect=studio_error))
    recommending = SimpleNamespace(recommend=AsyncMock(return_value=packages(), side_effect=package_error))
    scheduling = SimpleNamespace(schedule=AsyncMock(return_value=output(), side_effect=scheduling_error))
    graph = build_workflow(matching, recommending, scheduling)
    request = StudioMatchingInput(requirements=requirements(notes="PRIVATE customer notes"))
    async def run():
        stages, state = [], {}
        async for update in graph.astream({"scheduling": {"stale": "PRIVATE old response"}},
                context=MatchingContext(request), stream_mode="updates"):
            stages.extend(update)
            for values in update.values():
                state.update(values)
        return stages, state
    stages, state = asyncio.run(run())
    return stages, state, matching, recommending, scheduling, request


def test_success_stores_output_preserves_prior_state_and_event_order():
    stages, state, _, _, scheduling, request = execute()
    assert stages == ["Submitted", "StudioMatching", "PackageRecommendation", "Scheduling", "Validation", "Failed"]
    assert state["status"] == "Failed"
    assert state["blocked_stage"] == "Validation"
    assert state["error_code"] == "invalid_workflow_state"
    assert state["scheduling"] == output().model_dump(mode="json")
    assert state["studio_matching"] == studios().model_dump(mode="json")
    assert state["package_recommendation"] == packages().model_dump(mode="json")
    assert [event["eventType"] for event in state["events"]] == [
        "StudioMatchingCompleted", "PackageRecommendationCompleted", "SchedulingCompleted", "ValidationFailed"]
    assert all(event["success"] for event in state["events"][:-1])
    assert state["events"][-2]["stepName"] == "Scheduling"
    assert state["events"][-2]["detailsJson"] is None
    assert state["events"][-2]["durationMs"] >= 0
    scheduling.schedule.assert_awaited_once()
    supplied = scheduling.schedule.call_args.args
    assert supplied[0] == request.requirements
    assert supplied[1] == studios() and supplied[2] == packages()
    serialized = json.dumps(state)
    assert "PRIVATE" not in serialized
    assert "raw_response" not in serialized and "prompt" not in serialized and "api_key" not in serialized
    assert json.loads(serialized)["scheduling"]["rankedSlots"][0]["evidenceIds"] == ["backend-evidence"]
    assert "AwaitingApproval" not in stages and "Approved" not in stages


@pytest.mark.parametrize("code", ["invalid_scheduling_input", "package_unavailable", "no_available_slots",
    "backend_unavailable", "backend_timeout", "invalid_backend_response", "gemini_not_configured",
    "gemini_unavailable", "gemini_timeout", "invalid_gemini_output"])
def test_scheduling_failure_stops_and_clears_stale_output(code):
    stages, state, _, _, scheduling, _ = execute(scheduling_error=SchedulingFailure(code))
    assert stages == ["Submitted", "StudioMatching", "PackageRecommendation", "Scheduling", "Failed"]
    assert state["status"] == "Failed" and state["blocked_stage"] == "Scheduling"
    assert state["error_code"] == code and state["scheduling"] is None
    assert state["studio_matching"] and state["package_recommendation"]
    assert [event["eventType"] for event in state["events"]] == [
        "StudioMatchingCompleted", "PackageRecommendationCompleted", "SchedulingFailed"]
    event = state["events"][-1]
    assert event["success"] is False and event["stepName"] == "Scheduling"
    assert json.loads(event["detailsJson"]) == {"errorCode": code}
    assert "Validation" not in stages and "PRIVATE" not in json.dumps(state)
    scheduling.schedule.assert_awaited_once()


@pytest.mark.parametrize("stage", ["studio", "package"])
def test_earlier_failure_never_invokes_scheduling(stage):
    stages, state, _, recommending, scheduling, _ = execute(
        studio_error=MatchingFailure("no_matching_studios") if stage == "studio" else None,
        package_error=PackageFailure("no_matching_packages") if stage == "package" else None)
    assert state["status"] == "Failed" and state["scheduling"] is None
    assert state["blocked_stage"] == ("StudioMatching" if stage == "studio" else "PackageRecommendation")
    assert "Scheduling" not in stages and "Validation" not in stages
    scheduling.schedule.assert_not_awaited()
    if stage == "studio":
        recommending.recommend.assert_not_awaited()


def test_app_reuses_one_service_and_settings():
    settings = Settings(_env_file=None)
    app = create_app(settings)
    assert app.state.scheduling.llm is app.state.llm is app.state.package_recommendation.llm is app.state.studio_matching.llm
    assert app.state.scheduling.discovery.settings is settings


@pytest.mark.parametrize("status,code,expected", [("AwaitingApproval", None, 0),
    ("Failed", "gemini_unavailable", 1), ("Scheduling", "scheduling_agent_not_implemented", 1)])
def test_manual_runner_serializes_and_uses_new_boundary(monkeypatch, tmp_path, capsys, status, code, expected):
    from app import match_studios
    path = tmp_path / "request.json"
    path.write_text(StudioMatchingInput(requirements=requirements()).model_dump_json(), encoding="utf-8")
    result = {"status": status, "blocked_stage": status, "error_code": code,
              "scheduling": output().model_dump(mode="json") if status == "AwaitingApproval" else None}
    workflow = SimpleNamespace(ainvoke=AsyncMock(return_value=result))
    monkeypatch.setattr(match_studios, "Settings", lambda: Settings(_env_file=None))
    monkeypatch.setattr(match_studios, "create_app", lambda _: SimpleNamespace(state=SimpleNamespace(workflow=workflow)))
    monkeypatch.setattr("sys.argv", ["match_studios", str(path)])
    assert match_studios.main() == expected
    assert json.loads(capsys.readouterr().out) == result
