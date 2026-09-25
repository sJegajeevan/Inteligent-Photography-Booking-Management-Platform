"""Standalone deterministic Validation & Safety Agent. No LLM or workflow writes."""
from datetime import datetime, timedelta, timezone

from pydantic import ValidationError

from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput
from app.scheduling_contracts import SchedulingOutput
from app.validation_contracts import FinalValidationResult, ValidationRequirements, ValidationSelection
from app.validation_discovery import (
    ValidationDiscoveryFailure, ValidationDiscoveryTool, build_validation_request,
)


class ValidationFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class ValidationAgent:
    def __init__(self, discovery: ValidationDiscoveryTool):
        self.discovery = discovery

    async def validate(self, requirements: CustomerPhotographyRequirements, studios: StudioMatchingOutput,
                       packages: PackageRecommendationOutput, scheduling: SchedulingOutput,
                       selection: ValidationSelection) -> FinalValidationResult:
        try:
            # Detached snapshots protect the consistency checks across awaits.
            def snapshot(model, value):
                return model.model_validate(value.model_dump(warnings=False), strict=True)
            requirements = snapshot(ValidationRequirements, requirements)
            studios = snapshot(StudioMatchingOutput, studios)
            packages = snapshot(PackageRecommendationOutput, packages)
            scheduling = snapshot(SchedulingOutput, scheduling)
            selection = snapshot(ValidationSelection, selection)
            retained = {}
            candidate_ids = set()
            for evidence in scheduling.backendEvidence:
                key = (evidence.studioId.lower(), evidence.packageId.lower())
                if key in retained:
                    raise ValueError("Duplicate backend evidence")
                retained[key] = evidence
                for candidate in evidence.candidates:
                    if candidate.slotId.lower() in candidate_ids:
                        raise ValueError("Duplicate candidate evidence")
                    candidate_ids.add(candidate.slotId.lower())
            slot_keys = {(s.studioId.lower(), s.packageId.lower()) for s in scheduling.rankedSlots}
            if set(retained) != slot_keys:
                raise ValueError("Missing or unrelated backend evidence")
            # Validate every retained selected slot, not only the final choice.
            for slot in scheduling.rankedSlots:
                package = next(p for p in packages.rankedPackages if
                               (p.studioId, p.packageId) == (slot.studioId, slot.packageId))
                candidate_selection = ValidationSelection.model_validate({
                    **slot.model_dump(include={"studioId", "packageId", "date", "startTime", "endTime"}),
                    "customization": package.customization.model_dump()}, strict=True)
                build_validation_request(requirements, studios, packages, scheduling,
                    retained[(slot.studioId.lower(), slot.packageId.lower())], candidate_selection)
            evidence = retained[(selection.studioId.lower(), selection.packageId.lower())]
            request = build_validation_request(requirements, studios, packages, scheduling, evidence, selection)
        except (ValidationError, ValueError, TypeError, AttributeError, KeyError, StopIteration):
            raise ValidationFailure("invalid_workflow_state") from None

        try:
            result = await self.discovery.validate(requirements, studios, packages, scheduling, evidence, selection)
        except ValidationDiscoveryFailure as error:
            allowed = {"invalid_workflow_state", "validation_failed", "stale_recommendation", "price_changed",
                       "slot_unavailable", "booking_conflict", "invalid_backend_response",
                       "backend_timeout", "backend_unavailable"}
            raise ValidationFailure(error.code if error.code in allowed else "backend_unavailable") from None
        except TimeoutError:
            raise ValidationFailure("backend_timeout") from None
        except Exception:
            # Cancellation inherits BaseException and propagates unchanged.
            raise ValidationFailure("backend_unavailable") from None
        try:
            result = snapshot(FinalValidationResult, result)
            result.validate_for(request)
            now = datetime.now(timezone.utc)
            if (result.checkedAtUtc < request.priorEvidence.checkedAtUtc or
                    result.checkedAtUtc > now + timedelta(seconds=30) or
                    result.classification == "Pass" and result.evidenceExpiresAtUtc <= now):
                raise ValueError("Invalid backend freshness")
        except (ValidationError, ValueError, TypeError, AttributeError):
            raise ValidationFailure("invalid_backend_response") from None
        # Never synthesize Pass, publish proposals, or infer approval from this result.
        return result
