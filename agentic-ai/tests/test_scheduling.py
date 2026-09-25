"""Standalone Scheduling Agent checks; every external boundary is mocked."""
import asyncio
import json
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest

from app.config import Settings
from app.llm import AiUnavailable
from app.matching_contracts import StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput
from app.scheduling import SchedulingAgent, SchedulingFailure
from app.scheduling_discovery import SchedulingDiscoveryTool
from test_scheduling_discovery import SID, PID, SLOT, payload, requirements

REASON = "This backend candidate falls within the requested date range."
TIME_REASON = "This backend candidate fits entirely within the requested preferred time interval."
SLOT2 = "dddddddd-1234-4234-8234-123456789012"
PID2 = "eeeeeeee-1234-4234-8234-123456789012"


def studios():
    return StudioMatchingOutput(rankedStudios=[dict(studioId=SID, explanationSummary="Prior stage")], unmetPreferences=[])


def packages():
    return PackageRecommendationOutput.model_validate_json(json.dumps(dict(rankedPackages=[dict(
        studioId=SID, packageId=PID, explanationSummary="Prior stage",
        customization=dict(selectedAddonIds=[], extraHours=1, additionalPhotographers=0),
        pricing=dict(packageId=PID, packageName="Package", basePrice=50000, selectedAddons=[],
                     extraHours=1, extraHoursCost=1000, additionalPhotographers=0,
                     additionalPhotographersCost=0, finalPrice=51000))], unmetPreferences=[])))


def ranking(**changes):
    item = dict(slotId=SLOT, explanationSummary=REASON)
    item.update(changes)
    return json.dumps(dict(rankedSlots=[item]))


def execute(data=None, raw=None, error=None, handler=None, req=None, prior=None, matched=None):
    calls = []
    def backend(request):
        calls.append(request)
        assert request.method == "POST"
        assert request.url.path.endswith("/available-slots")
        return handler(request) if handler else httpx.Response(200, json=data if data is not None else payload())
    discovery = SchedulingDiscoveryTool(Settings(_env_file=None), transport=httpx.MockTransport(backend))
    llm = SimpleNamespace(rank_slots=AsyncMock(return_value=ranking() if raw is None else raw, side_effect=error))
    agent = SchedulingAgent(discovery, llm)
    async def run():
        try:
            return await agent.schedule(req or requirements(), matched or studios(), prior or packages())
        except SchedulingFailure as exc:
            return exc
    return asyncio.run(run()), llm, calls


def test_success_copies_authoritative_evidence_and_keeps_customization():
    prior = packages()
    before = prior.model_dump_json()
    data = payload()
    data["candidates"][0].update(startTime="08:00:00.1234567", endTime="12:00:00.1234567")
    result, llm, calls = execute(data=data, prior=prior, req=requirements(notes="PRIVATE notes", location="PRIVATE location"))
    slot = result.rankedSlots[0]
    assert slot.studioId == SID and slot.packageId == PID
    assert slot.startTime == "08:00:00.1234567" and slot.endTime == "12:00:00.1234567"
    assert slot.date.isoformat() == "2026-12-01"
    assert slot.evidenceIds == data["candidates"][0]["evidenceIds"]
    assert set(slot.model_dump()) == {"studioId", "packageId", "date", "startTime", "endTime", "explanationSummary", "evidenceIds"}
    assert prior.model_dump_json() == before
    assert json.loads(calls[0].content)["customization"] == prior.rankedPackages[0].customization.model_dump()
    assert calls[0].url.path == f"/api/public/studios/{SID}/packages/{PID}/available-slots"
    llm.rank_slots.assert_awaited_once()
    prompt = llm.rank_slots.call_args.args[0]
    assert "PRIVATE" not in prompt and "pricing" not in prompt and "customization" not in prompt
    assert json.loads(prompt)["candidates"][0]["isReservation"] is False
    assert any("not a reservation" in caveat for caveat in result.unmetPreferences)


def test_multiple_package_references_and_model_order_preserved():
    prior = packages()
    second = prior.rankedPackages[0].model_copy(deep=True)
    second.packageId = PID2
    second.pricing.packageId = PID2
    prior.rankedPackages.append(second)
    def backend(request):
        data = payload()
        if PID2 in request.url.path:
            data["packageId"] = PID2
            data["candidates"][0]["slotId"] = SLOT2
        return httpx.Response(200, json=data)
    raw = json.dumps(dict(rankedSlots=[dict(slotId=SLOT2, explanationSummary=REASON), dict(slotId=SLOT, explanationSummary=REASON)]))
    result, _, calls = execute(prior=prior, handler=backend, raw=raw)
    assert [s.packageId for s in result.rankedSlots] == [PID2, PID]
    assert len(calls) == 2


def test_preferred_reason_and_truncation_caveat():
    result, _, _ = execute(data=payload(truncated=True), raw=ranking(explanationSummary=TIME_REASON),
                           req=requirements(preferredStartTime="08:00:00", preferredEndTime="12:00:00"))
    assert result.rankedSlots[0].explanationSummary == TIME_REASON
    assert any("truncated" in text for text in result.unmetPreferences)


@pytest.mark.parametrize("raw", [
    ranking(slotId=SLOT2), ranking(slotId=SLOT.upper()), ranking(studioId=SID), ranking(packageId=PID),
    ranking(date="2026-12-01"), ranking(startTime="08:00:00"), ranking(endTime="12:00:00"),
    ranking(duration=4), ranking(availability=True), ranking(pricing=1), ranking(customization={}),
    ranking(isReservation=True), ranking(explanationSummary="Best weather and traffic."),
    ranking(explanationSummary=TIME_REASON), "not json", "{}", '{"rankedSlots": []}',
    json.dumps({"rankedSlots": json.loads(ranking())["rankedSlots"] * 2}),
    json.dumps({**json.loads(ranking()), "extra": "PRIVATE"}), "x" * 16001, 42,
], ids=lambda value: str(value)[:90])
def test_invalid_model_output_has_no_fallback(raw):
    result, llm, _ = execute(raw=raw)
    assert isinstance(result, SchedulingFailure) and result.code == "invalid_gemini_output"
    llm.rank_slots.assert_awaited_once()


@pytest.mark.parametrize("data,code", [(payload(candidates=[]), "no_available_slots"),
    (payload(isReservation=True), "invalid_backend_response"), (payload(packageId=PID2), "invalid_backend_response"),
    ({}, "invalid_backend_response")])
def test_backend_empty_and_invalid_never_call_gemini(data, code):
    result, llm, _ = execute(data=data)
    assert isinstance(result, SchedulingFailure) and result.code == code
    llm.rank_slots.assert_not_awaited()


@pytest.mark.parametrize("status,code", [(400, "invalid_scheduling_input"), (404, "package_unavailable"),
                                      (500, "backend_unavailable"), (503, "backend_unavailable")])
def test_backend_status_failures(status, code):
    result, llm, _ = execute(handler=lambda _: httpx.Response(status, text="PRIVATE details"))
    assert result.code == code and str(result) == code
    llm.rank_slots.assert_not_awaited()


def test_backend_timeout():
    def backend(request):
        raise httpx.ReadTimeout("PRIVATE", request=request)
    result, llm, _ = execute(handler=backend)
    assert result.code == "backend_timeout"
    llm.rank_slots.assert_not_awaited()


@pytest.mark.parametrize("source,expected", [("not_configured", "gemini_not_configured"), ("timeout", "gemini_timeout"),
    ("provider_unavailable", "gemini_unavailable"), ("malformed_structured_output", "invalid_gemini_output")])
def test_gemini_error_mapping_no_fallback(source, expected):
    result, llm, _ = execute(error=AiUnavailable(source))
    assert isinstance(result, SchedulingFailure) and result.code == expected
    llm.rank_slots.assert_awaited_once()


@pytest.mark.parametrize("change", ["studio", "quote_id", "quote_hours", "budget", "duplicate", "customization"])
def test_invalid_prior_stage_fails_before_external_calls(change):
    prior = packages()
    package = prior.rankedPackages[0]
    if change == "studio": package.studioId = PID2
    if change == "quote_id": package.pricing.packageId = PID2
    if change == "quote_hours": package.pricing.extraHours = 2
    if change == "budget": package.pricing.finalPrice = Decimal("100001")
    if change == "duplicate": prior.rankedPackages.append(package.model_copy(deep=True))
    if change == "customization": package.customization.selectedAddonIds.append(SID)
    result, llm, calls = execute(prior=prior)
    assert result.code == "invalid_scheduling_input"
    assert calls == []
    llm.rank_slots.assert_not_awaited()


def test_backend_duplicate_ids_across_packages_rejected():
    prior = packages()
    second = prior.rankedPackages[0].model_copy(deep=True)
    second.packageId = PID2
    second.pricing.packageId = PID2
    prior.rankedPackages.append(second)
    result, llm, _ = execute(prior=prior, handler=lambda req: httpx.Response(200, json=payload(
        packageId=PID2 if PID2 in req.url.path else PID)))
    assert result.code == "invalid_backend_response"
    llm.rank_slots.assert_not_awaited()
