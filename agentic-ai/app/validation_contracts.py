"""Strict Phase 4.4 ASP.NET wire evidence; no workflow commands or model output."""
from datetime import date, timedelta
from typing import Literal

from pydantic import AwareDatetime, ConfigDict, Field, model_validator

from app.matching_contracts import CustomerPhotographyRequirements, Money
from app.package_contracts import EntityId, PackageQuote
from app.scheduling_contracts import Duration, LocalTime, SchedulingContract, time_ticks


class ValidationRequirements(CustomerPhotographyRequirements):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True, revalidate_instances="always")


class ValidationCustomization(SchedulingContract):
    selectedAddonIds: list[EntityId] = Field(max_length=0)
    extraHours: int = Field(ge=0, le=1000)
    additionalPhotographers: int = Field(ge=0, le=0)


class ValidationSelection(SchedulingContract):
    studioId: EntityId
    packageId: EntityId
    date: date
    startTime: LocalTime
    endTime: LocalTime
    customization: ValidationCustomization

    @model_validator(mode="after")
    def interval(self):
        if self.date == date.min or time_ticks(self.startTime) >= time_ticks(self.endTime):
            raise ValueError("Invalid selected interval")
        return self


class FinalServiceEvidence(SchedulingContract):
    id: EntityId
    serviceName: str = Field(min_length=1)


def unique_services(services):
    if services is not None and (len({s.id.lower() for s in services}) != len(services) or
                                 any(not s.serviceName.strip() for s in services)):
        raise ValueError("Invalid service evidence")


class PriorRecommendationEvidence(SchedulingContract):
    selection: ValidationSelection
    quotedFinalPrice: Money
    packageDurationHours: Duration | None = None
    includedServices: list[FinalServiceEvidence] | None = None
    checkedAtUtc: AwareDatetime | None = None
    slotWasAvailable: bool

    @model_validator(mode="after")
    def evidence(self):
        unique_services(self.includedServices)
        if self.checkedAtUtc is not None and self.checkedAtUtc.utcoffset() != timedelta(0):
            raise ValueError("Expected UTC evidence")
        return self


class FinalValidationRequest(SchedulingContract):
    requirements: ValidationRequirements
    selection: ValidationSelection
    priorEvidence: PriorRecommendationEvidence
    timeZoneId: Literal["Asia/Colombo"] = "Asia/Colombo"

    @model_validator(mode="after")
    def matching_selection(self):
        if self.selection != self.priorEvidence.selection:
            raise ValueError("Inconsistent prior selection")
        return self


class ValidationFinding(SchedulingContract):
    code: Literal["invalid_workflow_state", "validation_failed", "stale_recommendation",
                  "price_changed", "slot_unavailable", "booking_conflict", "budget_failure", "backend_unavailable"]
    field: Literal["request", "selection", "constraints", "priorEvidence", "validation", "package",
                   "services", "duration", "pricing"]
    severity: Literal["Warning", "Error"]
    message: str


class ValidationSafetyOutput(SchedulingContract):
    outcome: Literal["Pass", "NeedsInput", "Fail"]
    findings: list[ValidationFinding]
    checkedAtUtc: AwareDatetime


class CurrentRecommendationEvidence(SchedulingContract):
    selection: ValidationSelection
    packageDurationHours: Duration
    requiredDurationHours: Duration
    includedServices: list[FinalServiceEvidence]
    pricing: PackageQuote | None

    @model_validator(mode="after")
    def evidence(self):
        unique_services(self.includedServices)
        if self.requiredDurationHours != self.packageDurationHours + self.selection.customization.extraHours:
            raise ValueError("Inconsistent duration evidence")
        if self.pricing is not None:
            quote, customization = self.pricing, self.selection.customization
            if (quote.packageId != self.selection.packageId or quote.extraHours != customization.extraHours or
                    quote.additionalPhotographers != customization.additionalPhotographers or quote.selectedAddons):
                raise ValueError("Inconsistent pricing evidence")
        return self


class FinalValidationResult(SchedulingContract):
    classification: Literal["Pass", "Fail", "RevalidationRequired"]
    validation: ValidationSafetyOutput
    current: CurrentRecommendationEvidence | None
    checkedAtUtc: AwareDatetime
    evidenceExpiresAtUtc: AwareDatetime
    priorTimestampAvailable: bool
    timeZoneId: Literal["Asia/Colombo"]
    isReservation: bool

    @model_validator(mode="after")
    def evidence(self):
        if (self.isReservation or self.checkedAtUtc.utcoffset() != timedelta(0) or
                self.evidenceExpiresAtUtc.utcoffset() != timedelta(0) or
                self.validation.checkedAtUtc.utcoffset() != timedelta(0) or
                self.validation.checkedAtUtc != self.checkedAtUtc or
                self.evidenceExpiresAtUtc - self.checkedAtUtc != timedelta(minutes=5)):
            raise ValueError("Invalid freshness or reservation evidence")
        errors = any(f.severity == "Error" for f in self.validation.findings)
        if self.classification == "Pass":
            if self.validation.outcome != "Pass" or errors or self.current is None or self.current.pricing is None:
                raise ValueError("Missing successful validation evidence")
        elif self.validation.outcome != "Fail" or not errors:
            raise ValueError("Inconsistent failed validation evidence")
        return self

    def validate_for(self, request: FinalValidationRequest) -> None:
        if self.priorTimestampAvailable != (request.priorEvidence.checkedAtUtc is not None):
            raise ValueError("Inconsistent timestamp availability")
        if self.current is not None and self.current.selection != request.selection:
            raise ValueError("Altered validated selection")
        if self.classification == "Pass" and (
                self.current.pricing.finalPrice != request.priorEvidence.quotedFinalPrice or
                self.current.packageDurationHours != request.priorEvidence.packageDurationHours or
                self.checkedAtUtc - request.priorEvidence.checkedAtUtc >= timedelta(minutes=5)):
            raise ValueError("Changed or stale evidence cannot pass")
