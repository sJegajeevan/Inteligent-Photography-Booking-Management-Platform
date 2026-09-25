"""Offline final-validation contract, provenance, and transport checks."""
import asyncio
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json

import httpx
import pytest

from app.config import Settings
from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput
from app.scheduling_contracts import SchedulingCandidateResponse, SchedulingOutput
from app.validation_contracts import FinalValidationRequest, ValidationSelection
from app.validation_discovery import ValidationDiscoveryFailure, ValidationDiscoveryTool

SID = "aaaaaaaa-1234-4234-8234-123456789012"
PID = "bbbbbbbb-1234-4234-8234-123456789012"
SLOT = "cccccccc-1234-4234-8234-123456789012"
NOW = datetime.now(timezone.utc).replace(microsecond=0)


def selection():
    return dict(studioId=SID, packageId=PID, date="2027-12-01", startTime="08:00:00", endTime="12:00:00",
                customization=dict(selectedAddonIds=[], extraHours=1, additionalPhotographers=0))


def quote():
    return dict(packageId=PID, packageName="Wedding", basePrice=70000, selectedAddons=[], extraHours=1,
                extraHoursCost=10000, additionalPhotographers=0, additionalPhotographersCost=0, finalPrice=80000)


def inputs():
    selected = selection()
    slot = {k: v for k, v in selected.items() if k != "customization"}
    slot.update(explanationSummary="Verified candidate", evidenceIds=["backend-evidence"])
    def parse(model, value):
        return model.model_validate_json(json.dumps(value), strict=True)
    return dict(
        requirements=parse(CustomerPhotographyRequirements, dict(photographyType="Wedding", location="Jaffna",
            maximumBudget=100000, earliestDate="2027-12-01", latestDate="2027-12-02", coverageHours=4,
            requestedServices=["Photography"])),
        studios=parse(StudioMatchingOutput, dict(rankedStudios=[dict(studioId=SID, explanationSummary="Matched")], unmetPreferences=[])),
        packages=parse(PackageRecommendationOutput, dict(rankedPackages=[dict(studioId=SID, packageId=PID,
            explanationSummary="Recommended", customization=selected["customization"], pricing=quote())], unmetPreferences=[])),
        scheduling=parse(SchedulingOutput, dict(rankedSlots=[slot], unmetPreferences=[])),
        scheduling_evidence=parse(SchedulingCandidateResponse, dict(studioId=SID, packageId=PID,
            timeZoneId="Asia/Colombo", packageDurationHours=3, extraHours=1, requiredDurationHours=4,
            checkedAtUtc=(NOW - timedelta(seconds=10)).isoformat(), isReservation=False, truncated=False,
            candidates=[dict(slotId=SLOT, date=slot["date"], startTime=slot["startTime"], endTime=slot["endTime"],
                             evidenceIds=slot["evidenceIds"])])),
        selection=parse(ValidationSelection, selected))


def payload(classification="Pass"):
    findings = [] if classification == "Pass" else [dict(code="validation_failed" if classification == "Fail" else "stale_recommendation",
        field="selection", severity="Error", message="Fresh backend selection checks did not pass.")]
    return dict(classification=classification, validation=dict(outcome="Pass" if classification == "Pass" else "Fail",
        findings=findings, checkedAtUtc=NOW.isoformat()), current=dict(selection=selection(), packageDurationHours=3,
        requiredDurationHours=4, includedServices=[dict(id=SLOT, serviceName="Photography")], pricing=quote()),
        checkedAtUtc=NOW.isoformat(), evidenceExpiresAtUtc=(NOW + timedelta(minutes=5)).isoformat(),
        priorTimestampAvailable=True, timeZoneId="Asia/Colombo", isReservation=False)


def tool(handler, timeout=10):
    return ValidationDiscoveryTool(Settings(_env_file=None, aspnet_api_base_url="http://backend.example:5284",
        aspnet_timeout_seconds=timeout), transport=httpx.MockTransport(handler))


def execute(data=None, *, state=None, handler=None):
    calls = []
    def backend(request):
        calls.append(request)
        return handler(request) if handler else httpx.Response(200, json=payload() if data is None else data)
    result = asyncio.run(tool(backend).validate(**(inputs() if state is None else state)))
    return result, calls


def rejected(code="invalid_backend_response", **kwargs):
    with pytest.raises(ValidationDiscoveryFailure) as error:
        execute(**kwargs)
    assert error.value.code == str(error.value) == code
    assert "PRIVATE" not in repr(error.value)
    assert error.value.__context__ is None or error.value.__suppress_context__


@pytest.mark.parametrize("classification", ["Pass", "Fail", "RevalidationRequired"])
def test_fixed_read_only_endpoint_preserves_classification(classification):
    state = inputs()
    before = {k: v.model_dump() for k, v in state.items()}
    result, calls = execute(payload(classification), state=state)
    assert result.classification == classification
    assert result.isReservation is False
    assert len(calls) == 1
    assert calls[0].method == "POST"
    assert str(calls[0].url) == f"http://backend.example:5284/api/public/studios/{SID}/packages/{PID}/validate-recommendation"
    request = FinalValidationRequest.model_validate_json(calls[0].content, strict=True)
    assert request.selection == request.priorEvidence.selection
    assert request.priorEvidence.quotedFinalPrice == 80000
    assert request.priorEvidence.slotWasAvailable is True
    assert request.priorEvidence.includedServices is None  # Never fabricate absent prior service evidence.
    assert before == {k: v.model_dump() for k, v in state.items()}


@pytest.mark.parametrize("classification", ["Fail", "RevalidationRequired"])
def test_domain_early_return_without_current_evidence(classification):
    data = payload(classification)
    data["current"] = None
    assert execute(data)[0].classification == classification


@pytest.mark.parametrize("path,value", [
    ("classification", "Approved"), ("classification", 0), ("unknown", "PRIVATE"),
    ("isReservation", True), ("isReservation", 0), ("isReservation", "false"),
    ("timeZoneId", "UTC"), ("checkedAtUtc", "bad"), ("checkedAtUtc", "2026-09-24T00:00:00"),
    ("checkedAtUtc", "9999-12-31T00:00:00Z"), ("evidenceExpiresAtUtc", NOW.isoformat()),
    ("priorTimestampAvailable", False), ("current", None), ("current.pricing", None),
    ("current.selection.studioId", PID), ("current.selection.packageId", SID),
    ("current.selection.studioId", "malformed"), ("current.selection.packageId", "00000000-0000-0000-0000-000000000000"),
    ("current.selection.customization.extraHours", 2), ("current.selection.customization.additionalPhotographers", False),
    ("current.selection.date", "2027-12-02"), ("current.selection.startTime", "09:00:00"),
    ("current.selection.endTime", "12:00:00.00000001"), ("current.pricing.packageId", SID),
    ("current.pricing.finalPrice", 90000), ("current.pricing.customerId", "PRIVATE"),
    ("current.includedServices.0.id", "bad"), ("validation.outcome", "Fail"),
    ("validation.checkedAtUtc", "2026-01-01T00:00:00Z"),
    ("validation.findings", [dict(code="PRIVATE", field="selection", severity="Error", message="PRIVATE")]),
])
def test_strict_response_rejection(path, value):
    data = payload()
    parts = path.split(".")
    target = data
    for part in parts[:-1]:
        target = target[int(part)] if isinstance(target, list) else target[part]
    target[parts[-1]] = value
    rejected(data=data)


@pytest.mark.parametrize("field", list(payload()))
def test_missing_response_fields(field):
    data = payload()
    del data[field]
    rejected(data=data)


@pytest.mark.parametrize("stage", list(inputs()))
def test_missing_prior_stage_never_calls_backend(stage):
    state = inputs()
    state[stage] = None
    rejected("invalid_workflow_state", state=state, handler=lambda _: pytest.fail("No IO allowed"))


@pytest.mark.parametrize("change", [
    lambda s: setattr(s["studios"].rankedStudios[0], "studioId", PID),
    lambda s: setattr(s["packages"].rankedPackages[0], "packageId", SID),
    lambda s: setattr(s["packages"].rankedPackages[0].pricing, "finalPrice", "PRIVATE"),
    lambda s: setattr(s["packages"].rankedPackages[0].pricing, "packageId", SID),
    lambda s: setattr(s["selection"].customization, "extraHours", 2),
    lambda s: setattr(s["selection"], "startTime", "09:00:00"),
    lambda s: setattr(s["scheduling"].rankedSlots[0], "evidenceIds", ["altered"]),
    lambda s: setattr(s["scheduling"].rankedSlots[0], "evidenceIds", ["same", "same"]),
    lambda s: s["studios"].rankedStudios.append(s["studios"].rankedStudios[0]),
    lambda s: s["packages"].rankedPackages.append(s["packages"].rankedPackages[0]),
    lambda s: s["scheduling"].rankedSlots.append(s["scheduling"].rankedSlots[0]),
    lambda s: s["scheduling_evidence"].candidates.clear(),
    lambda s: setattr(s["scheduling_evidence"], "isReservation", True),
    lambda s: setattr(s["scheduling_evidence"], "checkedAtUtc", NOW + timedelta(days=1)),
])
def test_altered_prior_stage_never_calls_backend(change):
    state = inputs()
    change(state)
    rejected("invalid_workflow_state", state=state, handler=lambda _: pytest.fail("No IO allowed"))


@pytest.mark.parametrize("field", ["studioId", "packageId"])
@pytest.mark.parametrize("value", ["https://evil.example", "../../bookings", SID + "?url=evil", "", None, 123])
def test_arbitrary_routes_never_reach_transport(field, value):
    state = inputs()
    setattr(state["selection"], field, value)
    rejected("invalid_workflow_state", state=state, handler=lambda _: pytest.fail("No IO allowed"))


@pytest.mark.parametrize("status,code", [(400, "invalid_workflow_state"), (500, "backend_unavailable"),
    (404, "backend_unavailable"), (401, "backend_unavailable"), (204, "backend_unavailable")])
def test_safe_http_errors(status, code):
    rejected(code, handler=lambda _: httpx.Response(status, text="PRIVATE credentials stack trace"))


@pytest.mark.parametrize("status", [301, 302, 307, 308])
def test_redirects_not_followed(status):
    calls = []
    def redirect(request):
        calls.append(request)
        return httpx.Response(status, headers={"location": "https://evil.example/api/bookings"})
    rejected("backend_unavailable", handler=redirect)
    assert len(calls) == 1


@pytest.mark.parametrize("exception,code", [(httpx.ReadTimeout, "backend_timeout"),
    (httpx.ConnectError, "backend_unavailable"), (httpx.RemoteProtocolError, "backend_unavailable")])
def test_safe_transport_errors(exception, code):
    def fail(request):
        raise exception("PRIVATE secret", request=request)
    rejected(code, handler=fail)


@pytest.mark.parametrize("body", [b"PRIVATE", b"{}", b"[]", b"null", b"x" * 1_000_001,
    b'{"classification":"Fail","classification":"Pass"}', b'\xff'],
    ids=["malformed", "missing", "array", "null", "oversized", "duplicate", "encoding"])
def test_malformed_oversized_duplicate_json(body):
    rejected(handler=lambda _: httpx.Response(200, content=body))


def test_nested_unknown_and_duplicate_service_evidence():
    data = payload()
    data["current"]["includedServices"].append(deepcopy(data["current"]["includedServices"][0]))
    rejected(data=data)


def test_snapshot_survives_mutation_during_await():
    state = inputs()
    def backend(_):
        state["selection"].customization.extraHours = 9
        state["scheduling"].rankedSlots.clear()
        return httpx.Response(200, json=payload())
    assert execute(state=state, handler=backend)[0].current.selection.customization.extraHours == 1


def test_timeout_and_cancellation_cleanup():
    class Waiting(httpx.AsyncBaseTransport):
        closed = False
        async def handle_async_request(self, request):
            await asyncio.sleep(10)
        async def aclose(self):
            self.closed = True
    async def run(cancel):
        transport = Waiting()
        adapter = ValidationDiscoveryTool(Settings(_env_file=None, aspnet_timeout_seconds=0.01 if not cancel else 10),
                                          transport=transport)
        task = asyncio.create_task(adapter.validate(**inputs()))
        if cancel:
            await asyncio.sleep(0.01)
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
        else:
            with pytest.raises(ValidationDiscoveryFailure, match="^backend_timeout$"):
                await task
        assert transport.closed
    asyncio.run(run(False))
    asyncio.run(run(True))


@pytest.mark.parametrize("shift", [timedelta(days=1), -timedelta(days=1)])
def test_impossible_consistent_timestamps(shift):
    data = payload()
    stamp = NOW + shift
    data["checkedAtUtc"] = data["validation"]["checkedAtUtc"] = stamp.isoformat()
    data["evidenceExpiresAtUtc"] = (stamp + timedelta(minutes=5)).isoformat()
    rejected(data=data)


@pytest.mark.parametrize("classification", ["Fail", "RevalidationRequired"])
def test_changed_price_and_duration_remain_domain_results(classification):
    data = payload(classification)
    data["current"]["pricing"]["finalPrice"] = 90000
    data["current"]["packageDurationHours"] = 4
    data["current"]["requiredDurationHours"] = 5
    data["validation"]["findings"][0]["code"] = "price_changed"
    result = execute(data)[0]
    assert result.classification == classification
    assert result.validation.findings[0].code == "price_changed"
    assert result.current.pricing.finalPrice == 90000


@pytest.mark.parametrize("classification", ["Fail", "RevalidationRequired"])
def test_nonpass_requires_failed_evidence(classification):
    data = payload(classification)
    data["validation"]["findings"] = []
    rejected(data=data)


def test_stale_prior_cannot_pass_but_revalidation_is_preserved():
    state = inputs()
    state["scheduling_evidence"].checkedAtUtc = NOW - timedelta(minutes=6)
    rejected(state=state)
    assert execute(payload("RevalidationRequired"), state=state)[0].classification == "RevalidationRequired"


def test_precise_times_survive_request_and_response():
    state, data = inputs(), payload()
    for field in ("startTime", "endTime"):
        value = getattr(state["selection"], field) + ".1234567"
        for model in (state["selection"], state["scheduling"].rankedSlots[0], state["scheduling_evidence"].candidates[0]):
            setattr(model, field, value)
        data["current"]["selection"][field] = value
    result, calls = execute(data, state=state)
    assert result.current.selection.startTime == "08:00:00.1234567"
    assert json.loads(calls[0].content)["selection"]["endTime"] == "12:00:00.1234567"


def test_streamed_size_limit_closes_response():
    class LargeStream(httpx.AsyncByteStream):
        closed = False
        async def __aiter__(self):
            for _ in range(11):
                yield b"x" * 100_000
        async def aclose(self):
            self.closed = True
    stream = LargeStream()
    rejected(handler=lambda _: httpx.Response(200, stream=stream))
    assert stream.closed


def test_nested_request_contracts_forbid_unknown_fields():
    _, calls = execute()
    original = json.loads(calls[0].content)
    from pydantic import ValidationError
    for path in ((), ("requirements",), ("selection",), ("selection", "customization"),
                 ("priorEvidence",), ("priorEvidence", "selection")):
        body = deepcopy(original)
        target = body
        for key in path:
            target = target[key]
        target["arbitraryUrl"] = "https://evil.example/api/bookings"
        with pytest.raises(ValidationError):
            FinalValidationRequest.model_validate_json(json.dumps(body), strict=True)
