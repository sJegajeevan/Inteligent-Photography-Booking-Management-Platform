"""Standalone scheduling ranking. Not wired into the workflow until Phase 4.3 Step 5."""
import asyncio
import json

from pydantic import ValidationError

from app.llm import AiUnavailable, GeminiService
from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput, validate_id
from app.scheduling_contracts import (
    ProposedSlot, SchedulingCandidateRequest, SchedulingCandidateResponse,
    SchedulingOutput, SchedulingRanking,
)
from app.scheduling_discovery import SchedulingDiscoveryFailure, SchedulingDiscoveryTool


class SchedulingFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class SchedulingAgent:
    def __init__(self, discovery: SchedulingDiscoveryTool, llm: GeminiService):
        self.discovery = discovery
        self.llm = llm

    async def schedule(self, requirements: CustomerPhotographyRequirements,
                       studios: StudioMatchingOutput, packages: PackageRecommendationOutput) -> SchedulingOutput:
        try:
            # Detached, revalidated snapshots: mutable prior-stage state cannot change during awaits.
            requirements = CustomerPhotographyRequirements.model_validate(requirements.model_dump(), strict=True)
            studios = StudioMatchingOutput.model_validate(studios.model_dump(), strict=True)
            packages = PackageRecommendationOutput.model_validate(packages.model_dump(), strict=True)
            studio_ids = [validate_id(studio.studioId) for studio in studios.rankedStudios]
            if not studio_ids or len({sid.lower() for sid in studio_ids}) != len(studio_ids):
                raise ValueError("Invalid matched studios")
            seen_packages = set()
            requests = []
            for package in packages.rankedPackages:
                if package.studioId not in studio_ids or package.packageId.lower() in seen_packages:
                    raise ValueError("Invalid recommended package reference")
                seen_packages.add(package.packageId.lower())
                quote, customization = package.pricing, package.customization
                if (quote.packageId != package.packageId or quote.extraHours != customization.extraHours or
                    quote.additionalPhotographers != customization.additionalPhotographers or
                    [addon.id for addon in quote.selectedAddons] != customization.selectedAddonIds or
                    quote.finalPrice > requirements.maximumBudget or
                    (requirements.minimumBudget is not None and quote.finalPrice < requirements.minimumBudget)):
                    raise ValueError("Inconsistent prior-stage recommendation evidence")
                requests.append(SchedulingCandidateRequest.from_requirements(requirements, customization))
        except (ValidationError, ValueError, TypeError, AttributeError):
            raise SchedulingFailure("invalid_scheduling_input") from None

        candidates = {}
        seen_slots = set()
        truncated = False
        try:
            # At most five recommended packages, each with at most 50 backend candidates.
            # The shared deadline bounds the entire serial discovery phase.
            async with asyncio.timeout(self.discovery.settings.aspnet_timeout_seconds):
                for package, request in zip(packages.rankedPackages, requests, strict=True):
                    response = await self.discovery.discover(package.studioId, package.packageId,
                                                             requirements, request.customization)
                    try:
                        response = SchedulingCandidateResponse.model_validate(response.model_dump(), strict=True)
                        response.validate_for(package.studioId, package.packageId, request)
                    except (ValidationError, ValueError, TypeError, AttributeError):
                        raise SchedulingFailure("invalid_backend_response") from None
                    truncated |= response.truncated
                    for candidate in response.candidates:
                        if candidate.slotId.lower() in seen_slots:
                            raise SchedulingFailure("invalid_backend_response")
                        seen_slots.add(candidate.slotId.lower())
                        reasons = ["This backend candidate falls within the requested date range."]
                        if requirements.preferredStartTime is not None:
                            reasons.append("This backend candidate fits entirely within the requested preferred time interval.")
                        candidates[candidate.slotId] = (response, candidate, reasons)
        except TimeoutError:
            raise SchedulingFailure("backend_timeout") from None
        except SchedulingDiscoveryFailure as exc:
            raise SchedulingFailure(exc.code) from None
        if not candidates:
            raise SchedulingFailure("no_available_slots")

        payload = json.dumps({
            "requirements": requirements.model_dump(mode="json", include={
                "earliestDate", "latestDate", "preferredStartTime", "preferredEndTime", "coverageHours", "timeZoneId"}),
            "candidates": [{**candidate.model_dump(mode="json"),
                "requiredDurationHours": str(response.requiredDurationHours),
                "checkedAtUtc": response.checkedAtUtc.isoformat(), "isReservation": False,
                "allowedReasons": reasons} for response, candidate, reasons in candidates.values()],
        })
        try:
            raw = await self.llm.rank_slots(payload)
        except AiUnavailable as exc:
            code = {"not_configured": "gemini_not_configured", "timeout": "gemini_timeout",
                    "malformed_structured_output": "invalid_gemini_output"}.get(exc.code, "gemini_unavailable")
            raise SchedulingFailure(code) from None
        try:
            if not isinstance(raw, str) or len(raw) > 16000:
                raise ValueError("Invalid ranking payload")
            ranking = SchedulingRanking.model_validate_json(raw, strict=True)
        except (ValidationError, ValueError):
            raise SchedulingFailure("invalid_gemini_output") from None
        selected, output = set(), []
        retained = {}
        for match in ranking.rankedSlots:
            if match.slotId not in candidates or match.slotId.lower() in selected:
                raise SchedulingFailure("invalid_gemini_output")
            selected.add(match.slotId.lower())
            response, candidate, reasons = candidates[match.slotId]
            retained[(response.studioId, response.packageId)] = response.model_copy(deep=True)
            if match.explanationSummary not in reasons:
                raise SchedulingFailure("invalid_gemini_output")
            output.append(ProposedSlot(studioId=response.studioId, packageId=response.packageId,
                date=candidate.date, startTime=candidate.startTime, endTime=candidate.endTime,
                evidenceIds=list(candidate.evidenceIds), explanationSummary=match.explanationSummary))
        caveats = ["Scheduling evidence is point-in-time only, not a reservation. Final booking requires backend revalidation.",
                   "Only the supplied backend candidate sample was ranked; other start times may exist."]
        if truncated:
            caveats.append("At least one backend candidate search was truncated.")
        if requirements.notes:
            caveats.append("Additional notes have not been verified.")
        return SchedulingOutput(rankedSlots=output, unmetPreferences=caveats, backendEvidence=list(retained.values()))
