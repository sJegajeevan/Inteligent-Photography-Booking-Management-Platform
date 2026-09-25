"""Offline scheduling transport checks; no real backend, database or Gemini."""
import asyncio
from copy import deepcopy
from datetime import time
import json
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from app.config import Settings
from app.matching_contracts import CustomerPhotographyRequirements
from app.package_contracts import PackageCustomization
from app.scheduling_contracts import SchedulingCandidateRequest
from app.scheduling_discovery import SchedulingDiscoveryFailure, SchedulingDiscoveryTool

SID = "aaaaaaaa-1234-4234-8234-123456789012"
PID = "bbbbbbbb-1234-4234-8234-123456789012"
SLOT = "cccccccc-1234-4234-8234-123456789012"


def requirements(**changes):
    values = dict(photographyType="Wedding", location="Jaffna", maximumBudget=100000,
                  earliestDate="2026-12-01", latestDate="2026-12-02", coverageHours=4,
                  requestedServices=["Photography"])
    values.update(changes)
    return CustomerPhotographyRequirements(**values)


def payload(**changes):
    values = dict(studioId=SID, packageId=PID, timeZoneId="Asia/Colombo",
                  packageDurationHours=3, extraHours=1, requiredDurationHours=4,
                  checkedAtUtc="2026-09-23T00:00:00Z", isReservation=False, truncated=False,
                  candidates=[dict(slotId=SLOT, date="2026-12-01", startTime="08:00:00",
                                   endTime="12:00:00", evidenceIds=["opaque-evidence"])])
    values.update(changes)
    return values


def execute(data=None, *, handler=None, req=None, customization=None, sid=SID, pid=PID, timeout=10):
    calls = []
    def backend(request):
        calls.append(request)
        return handler(request) if handler else httpx.Response(200, json=payload() if data is None else data)
    tool = SchedulingDiscoveryTool(Settings(_env_file=None, aspnet_api_base_url="http://backend.example:5284",
                                             aspnet_timeout_seconds=timeout), transport=httpx.MockTransport(backend))
    return asyncio.run(tool.discover(sid, pid, req or requirements(),
                                    customization if customization is not None else PackageCustomization(extraHours=1))), calls


def rejected(code, **kwargs):
    with pytest.raises(SchedulingDiscoveryFailure) as error:
        execute(**kwargs)
    assert error.value.code == code
    assert str(error.value) == code
    assert "PRIVATE" not in str(error.value)


def test_fixed_post_and_trusted_request_without_mutation():
    customization = PackageCustomization(extraHours=1)
    before = customization.model_dump()
    result, calls = execute(customization=customization)
    assert result.studioId == SID and result.candidates[0].slotId == SLOT
    assert len(calls) == 1
    call = calls[0]
    assert call.method == "POST"
    assert str(call.url) == f"http://backend.example:5284/api/public/studios/{SID}/packages/{PID}/available-slots"
    body = json.loads(call.content)
    assert set(body) == {"earliestDate", "latestDate", "preferredStartTime", "preferredEndTime",
                         "coverageHours", "timeZoneId", "customization"}
    assert body["customization"] == before == customization.model_dump()
    assert body["coverageHours"] == "4"
    assert result.isReservation is False


def test_empty_candidates_is_success():
    assert execute(payload(candidates=[]))[0].candidates == []


@pytest.mark.parametrize("changes", [
    {"isReservation": True}, {"isReservation": 0}, {"isReservation": "false"},
    {"studioId": PID}, {"packageId": SID}, {"studioId": "not-a-uuid"},
    {"extraHours": 0}, {"extraHours": True}, {"extraHours": 2, "requiredDurationHours": 5, "candidates": []},
    {"requiredDurationHours": 5}, {"packageDurationHours": 0},
    {"requiredDurationHours": "NaN"}, {"timeZoneId": "UTC"}, {"truncated": "false"},
    {"checkedAtUtc": "not-a-date"}, {"checkedAtUtc": "2026-09-23T00:00:00"},
    {"checkedAtUtc": "2026-09-23T00:00:00+05:30"}, {"bookingId": 123},
])
def test_bad_response_evidence_rejected(changes):
    rejected("invalid_backend_response", data=payload(**changes))


@pytest.mark.parametrize("changes", [
    {"slotId": "not-a-uuid"}, {"slotId": "00000000-0000-0000-0000-000000000000"},
    {"date": "2026-02-30"}, {"date": "2026-12-03"}, {"date": "2026-11-30"},
    {"startTime": "12:00:00"}, {"endTime": "07:00:00"}, {"endTime": "11:59:59"},
    {"endTime": "13:00:00"}, {"startTime": "08:00:00Z"}, {"startTime": "25:00:00"},
    {"endTime": "12:00:00.00000001"}, {"evidenceIds": []},
    {"evidenceIds": ["same", "same"]}, {"evidenceIds": [" "]}, {"notes": "PRIVATE"},
])
def test_bad_candidate_rejected(changes):
    data = payload()
    data["candidates"][0].update(changes)
    rejected("invalid_backend_response", data=data)


def test_duplicate_slot_ids_case_insensitive():
    data = payload()
    duplicate = deepcopy(data["candidates"][0])
    duplicate["slotId"] = SLOT.upper()
    data["candidates"].append(duplicate)
    rejected("invalid_backend_response", data=data)


def test_precise_backend_times_preserved():
    data = payload()
    data["candidates"][0].update(startTime="08:00:00.1234567", endTime="12:00:00.1234567")
    candidate = execute(data)[0].candidates[0]
    assert candidate.startTime == "08:00:00.1234567"
    assert candidate.endTime == "12:00:00.1234567"


def test_preferred_times_are_consistency_checks():
    execute(req=requirements(preferredStartTime="08:00:00", preferredEndTime="12:00:00"))
    rejected("invalid_backend_response", req=requirements(preferredStartTime="09:00:00", preferredEndTime="13:00:00"))
    rejected("invalid_backend_response", req=requirements(preferredStartTime="07:00:00", preferredEndTime="11:00:00"))


def test_insufficient_backend_coverage_rejected_even_when_empty():
    rejected("invalid_backend_response", req=requirements(coverageHours=5), data=payload(candidates=[]))


@pytest.mark.parametrize("status,code", [(400, "invalid_scheduling_input"), (404, "package_unavailable"),
    (500, "backend_unavailable"), (503, "backend_unavailable"), (401, "backend_unavailable"),
    (204, "backend_unavailable")])
def test_status_mapping_hides_body(status, code):
    rejected(code, handler=lambda _: httpx.Response(status, text="PRIVATE server exception"))


@pytest.mark.parametrize("exception,code", [(httpx.ReadTimeout, "backend_timeout"),
    (httpx.ConnectError, "backend_unavailable"), (httpx.RemoteProtocolError, "backend_unavailable")])
def test_transport_errors_safe(exception, code):
    def fail(request):
        raise exception("PRIVATE URL credentials", request=request)
    rejected(code, handler=fail)


@pytest.mark.parametrize("content", [b"PRIVATE not json", b"{}", b"[]", b"null", b"x" * 1_000_001],
                         ids=["malformed", "missing-fields", "array", "null", "oversized"])
def test_malformed_or_oversized_body(content):
    rejected("invalid_backend_response", handler=lambda _: httpx.Response(200, content=content))


@pytest.mark.parametrize("status", [301, 302, 307, 308])
def test_redirects_never_followed(status):
    calls = []
    def redirect(request):
        calls.append(request)
        return httpx.Response(status, headers={"location": "http://elsewhere.example/api/bookings"})
    rejected("backend_unavailable", handler=redirect)
    assert len(calls) == 1


@pytest.mark.parametrize("value", ["https://elsewhere.example", "../../bookings", SID + "/../../bookings",
                                  SID + "?path=bookings", "", "00000000-0000-0000-0000-000000000000", None, 123])
@pytest.mark.parametrize("field", ["sid", "pid"])
def test_no_arbitrary_or_write_route(value, field):
    def forbidden(_):
        pytest.fail("Invalid reference must not reach transport")
    rejected("invalid_scheduling_input", handler=forbidden, **{field: value})


def test_limits_and_nested_customization_revalidation():
    rejected("invalid_scheduling_input", req=requirements(latestDate="2027-01-01"))
    execute(req=requirements(latestDate="2026-12-31"))
    data = payload()
    data["candidates"] = [dict(data["candidates"][0], slotId=str(uuid4())) for _ in range(51)]
    rejected("invalid_backend_response", data=data)
    for field, value in [("selectedAddonIds", [SID]), ("extraHours", -1), ("additionalPhotographers", 1),
                         ("additionalPhotographers", False)]:
        customization = PackageCustomization(extraHours=1)
        setattr(customization, field, value)
        rejected("invalid_scheduling_input", customization=customization)


def test_request_is_detached_from_phase42_state():
    original = PackageCustomization(extraHours=1)
    request = SchedulingCandidateRequest.from_requirements(requirements(), original)
    original.extraHours = 9
    original.selectedAddonIds.append(SID)
    assert request.customization.extraHours == 1
    assert request.customization.selectedAddonIds == []


@pytest.mark.parametrize("changes", [{"preferredStartTime": time(8)}, {"timeZoneId": "UTC"},
                                    {"coverageHours": 0}, {"extraField": "PRIVATE"}])
def test_request_contract_rejects_invalid_fields(changes):
    values = SchedulingCandidateRequest.from_requirements(requirements(), PackageCustomization(extraHours=1)).model_dump()
    values.update(changes)
    with pytest.raises(ValidationError):
        SchedulingCandidateRequest.model_validate(values)


def test_total_deadline_and_client_cleanup():
    class SlowTransport(httpx.AsyncBaseTransport):
        closed = False
        async def handle_async_request(self, request):
            await asyncio.sleep(1)
            pytest.fail("Expected bounded deadline")
        async def aclose(self):
            self.closed = True
    transport = SlowTransport()
    tool = SchedulingDiscoveryTool(Settings(_env_file=None, aspnet_timeout_seconds=0.01), transport=transport)
    with pytest.raises(SchedulingDiscoveryFailure, match="^backend_timeout$"):
        asyncio.run(tool.discover(SID, PID, requirements(), PackageCustomization(extraHours=1)))
    assert transport.closed
