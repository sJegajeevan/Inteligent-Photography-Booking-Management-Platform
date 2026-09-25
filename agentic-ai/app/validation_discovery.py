"""Standalone read-only final validation adapter. Call only with trusted stage snapshots.

The caller must retain ASP.NET scheduling evidence: opaque evidence IDs alone do
not establish availability. This module neither executes nor updates a workflow.
"""
import asyncio
from datetime import datetime, timedelta, timezone
import json

import httpx
from pydantic import ValidationError

from app.config import Settings
from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput, validate_id
from app.scheduling_contracts import SchedulingCandidateRequest, SchedulingCandidateResponse, SchedulingOutput
from app.validation_contracts import (
    FinalValidationRequest, FinalValidationResult, PriorRecommendationEvidence,
    ValidationRequirements, ValidationSelection,
)


class ValidationDiscoveryFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def _unique(values):
    if len(set(values)) != len(values):
        raise ValueError("Duplicate prior evidence")


def _snapshot(model, value):
    return model.model_validate(value.model_dump(warnings=False), strict=True)


def build_validation_request(requirements, studios, packages, scheduling, scheduling_evidence, selection):
    """Detach and verify trusted stage evidence before any backend IO."""
    requirements = _snapshot(ValidationRequirements, requirements)
    studios = _snapshot(StudioMatchingOutput, studios)
    packages = _snapshot(PackageRecommendationOutput, packages)
    scheduling = _snapshot(SchedulingOutput, scheduling)
    evidence = _snapshot(SchedulingCandidateResponse, scheduling_evidence)
    selection = _snapshot(ValidationSelection, selection)
    studio_ids = [validate_id(s.studioId) for s in studios.rankedStudios]
    _unique([sid.lower() for sid in studio_ids])
    _unique([p.packageId.lower() for p in packages.rankedPackages])
    for package in packages.rankedPackages:
        quote, customization = package.pricing, package.customization
        if (package.studioId not in studio_ids or quote.packageId != package.packageId or
                type(customization.additionalPhotographers) is not int or
                quote.extraHours != customization.extraHours or
                quote.additionalPhotographers != customization.additionalPhotographers or quote.selectedAddons):
            raise ValueError("Inconsistent package stage")
    package = next(p for p in packages.rankedPackages if p.packageId == selection.packageId and
                   p.studioId == selection.studioId)
    if selection.customization.model_dump() != package.customization.model_dump():
        raise ValueError("Altered customization")
    slots = scheduling.rankedSlots
    _unique([(s.studioId.lower(), s.packageId.lower(), s.date, s.startTime, s.endTime) for s in slots])
    for slot in slots:
        if not any(p.studioId == slot.studioId and p.packageId == slot.packageId for p in packages.rankedPackages):
            raise ValueError("Inconsistent scheduling stage")
        _unique(slot.evidenceIds)
        if any(not item.strip() for item in slot.evidenceIds):
            raise ValueError("Invalid scheduling evidence")
    slot = next(s for s in slots if (s.studioId, s.packageId, s.date, s.startTime, s.endTime) ==
                (selection.studioId, selection.packageId, selection.date, selection.startTime, selection.endTime))
    evidence.validate_for(package.studioId, package.packageId,
                          SchedulingCandidateRequest.from_requirements(requirements, package.customization))
    matches = [c for c in evidence.candidates if (c.date, c.startTime, c.endTime, c.evidenceIds) ==
               (slot.date, slot.startTime, slot.endTime, slot.evidenceIds)]
    if len(matches) != 1 or evidence.checkedAtUtc > datetime.now(timezone.utc):
        raise ValueError("Missing or ambiguous scheduling evidence")
    # IDs, quote and availability originate in verified prior stages, never user text.
    return FinalValidationRequest(requirements=requirements, selection=selection,
        priorEvidence=PriorRecommendationEvidence(selection=selection, quotedFinalPrice=package.pricing.finalPrice,
            packageDurationHours=evidence.packageDurationHours, checkedAtUtc=evidence.checkedAtUtc,
            slotWasAvailable=True))


def _no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate response field")
        result[key] = value
    return result


class ValidationDiscoveryTool:
    def __init__(self, settings: Settings, *, transport: httpx.AsyncBaseTransport | None = None):
        # Snapshot validated configuration; mutable caller state cannot redirect an in-flight call.
        settings = Settings.model_validate(settings.model_dump())
        self._base_url = str(settings.aspnet_api_base_url)
        self._timeout = settings.aspnet_timeout_seconds
        self._transport = transport

    async def validate(self, requirements: CustomerPhotographyRequirements, studios: StudioMatchingOutput,
                       packages: PackageRecommendationOutput, scheduling: SchedulingOutput,
                       scheduling_evidence: SchedulingCandidateResponse,
                       selection: ValidationSelection) -> FinalValidationResult:
        try:
            request = build_validation_request(requirements, studios, packages, scheduling, scheduling_evidence, selection)
        except (ValidationError, ValueError, TypeError, AttributeError, StopIteration):
            raise ValidationDiscoveryFailure("invalid_workflow_state") from None
        trusted = request.priorEvidence.selection
        path = f"/api/public/studios/{trusted.studioId}/packages/{trusted.packageId}/validate-recommendation"
        try:
            async with asyncio.timeout(self._timeout):
                async with httpx.AsyncClient(base_url=self._base_url, timeout=self._timeout,
                        follow_redirects=False, trust_env=False, transport=self._transport) as client:
                    async with client.stream("POST", path, json=request.model_dump(mode="json")) as response:
                        if response.status_code == 400:
                            raise ValidationDiscoveryFailure("invalid_workflow_state")
                        if response.status_code != 200:
                            raise ValidationDiscoveryFailure("backend_unavailable")
                        raw = bytearray()
                        async for chunk in response.aiter_bytes():
                            if len(raw) + len(chunk) > 1_000_000:
                                raise ValidationDiscoveryFailure("invalid_backend_response")
                            raw.extend(chunk)
            json.loads(raw, object_pairs_hook=_no_duplicate_keys)
            result = FinalValidationResult.model_validate_json(bytes(raw), strict=True)
            result.validate_for(request)
            if (result.checkedAtUtc > datetime.now(timezone.utc) + timedelta(seconds=30) or
                    result.checkedAtUtc < request.priorEvidence.checkedAtUtc):
                raise ValueError("Impossible validation timestamp")
            if result.classification == "Pass" and result.evidenceExpiresAtUtc <= datetime.now(timezone.utc):
                raise ValueError("Expired successful evidence")
            # Return the backend classification unchanged, including stale/domain failures.
            return result
        except (TimeoutError, httpx.TimeoutException):
            raise ValidationDiscoveryFailure("backend_timeout") from None
        except httpx.HTTPError:
            raise ValidationDiscoveryFailure("backend_unavailable") from None
        except (ValidationError, ValueError, TypeError, RecursionError):
            raise ValidationDiscoveryFailure("invalid_backend_response") from None
