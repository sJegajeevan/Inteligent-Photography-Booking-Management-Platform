"""Strict scheduling evidence, constrained rankings, and Phase 1 output contracts."""
from datetime import date, time, timedelta
from decimal import Decimal, ROUND_CEILING
from typing import Annotated, Literal

from pydantic import AwareDatetime, ConfigDict, Field, field_validator, model_validator

from app.matching_contracts import Contract, CustomerPhotographyRequirements
from app.package_contracts import EntityId, PackageCustomization


# TimeOnly has 100ns precision; datetime.time would silently lose the seventh digit.
LocalTime = Annotated[str, Field(pattern=r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,7})?$")]
Duration = Annotated[Decimal, Field(gt=0, le=24, allow_inf_nan=False)]
EvidenceId = Annotated[str, Field(min_length=1, max_length=128)]
TICKS_PER_HOUR = 36_000_000_000


def time_ticks(value: str | time) -> int:
    """Compare wire intervals without truncating authoritative backend precision."""
    if isinstance(value, time):
        return (value.hour * 3600 + value.minute * 60 + value.second) * 10_000_000 + value.microsecond * 10
    whole, _, fraction = value.partition(".")
    hour, minute, second = map(int, whole.split(":"))
    return (hour * 3600 + minute * 60 + second) * 10_000_000 + int(fraction.ljust(7, "0"))


class SchedulingContract(Contract):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True, revalidate_instances="always")


class SchedulingCandidateRequest(SchedulingContract):
    earliestDate: date
    latestDate: date
    preferredStartTime: time | None = None
    preferredEndTime: time | None = None
    coverageHours: Duration
    timeZoneId: Literal["Asia/Colombo"] = "Asia/Colombo"
    customization: PackageCustomization

    @field_validator("customization", mode="before")
    @classmethod
    def copy_customization(cls, value):
        # Revalidate even existing mutable models; never share/mutate Phase 4.2 state.
        if isinstance(value, PackageCustomization):
            value = value.model_dump()
        if isinstance(value, dict) and type(value.get("additionalPhotographers", 0)) is not int:
            raise ValueError("Expected integer photographer count")
        return value

    @model_validator(mode="after")
    def constraints(self):
        if self.earliestDate == date.min or not 0 <= (self.latestDate - self.earliestDate).days < 31:
            raise ValueError("Expected at most 31 inclusive days")
        start, end = self.preferredStartTime, self.preferredEndTime
        if (start is None) != (end is None):
            raise ValueError("Paired preferred times required")
        if start is not None and (start.tzinfo is not None or end.tzinfo is not None or start >= end):
            raise ValueError("Ordered local preferred times required")
        return self

    @classmethod
    def from_requirements(cls, requirements: CustomerPhotographyRequirements, customization: PackageCustomization):
        return cls(**requirements.model_dump(include={"earliestDate", "latestDate", "preferredStartTime",
            "preferredEndTime", "coverageHours", "timeZoneId"}), customization=customization)


class SchedulingCandidate(SchedulingContract):
    slotId: EntityId
    date: date
    startTime: LocalTime
    endTime: LocalTime
    evidenceIds: list[EvidenceId] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def valid_interval(self):
        if self.date == date.min or time_ticks(self.endTime) <= time_ticks(self.startTime):
            raise ValueError("Expected an ordered same-day interval")
        if any(not value.strip() for value in self.evidenceIds) or len(set(self.evidenceIds)) != len(self.evidenceIds):
            raise ValueError("Expected nonblank unique evidence references")
        return self


class SchedulingCandidateResponse(SchedulingContract):
    studioId: EntityId
    packageId: EntityId
    timeZoneId: Literal["Asia/Colombo"]
    packageDurationHours: Duration
    extraHours: int = Field(ge=0, le=1000)
    requiredDurationHours: Duration
    checkedAtUtc: AwareDatetime
    isReservation: bool
    truncated: bool
    candidates: list[SchedulingCandidate] = Field(max_length=50)

    @model_validator(mode="after")
    def evidence_consistency(self):
        if self.isReservation or self.checkedAtUtc.utcoffset() != timedelta(0):
            raise ValueError("Expected non-reservation UTC evidence")
        if self.requiredDurationHours != self.packageDurationHours + self.extraHours:
            raise ValueError("Inconsistent duration evidence")
        ids = [candidate.slotId.lower() for candidate in self.candidates]
        if len(set(ids)) != len(ids):
            raise ValueError("Duplicate slot reference")
        required_ticks = int((self.requiredDurationHours * TICKS_PER_HOUR).to_integral_value(rounding=ROUND_CEILING))
        if any(time_ticks(c.endTime) - time_ticks(c.startTime) != required_ticks for c in self.candidates):
            raise ValueError("Candidate duration differs from backend evidence")
        return self

    def validate_for(self, studio_id: str, package_id: str, request: SchedulingCandidateRequest) -> None:
        if (self.studioId != studio_id or self.packageId != package_id or self.timeZoneId != request.timeZoneId or
                self.extraHours != request.customization.extraHours or self.requiredDurationHours < request.coverageHours):
            raise ValueError("Response does not match requested evidence")
        for candidate in self.candidates:
            if not request.earliestDate <= candidate.date <= request.latestDate:
                raise ValueError("Candidate outside requested dates")
            if request.preferredStartTime is not None and (
                time_ticks(candidate.startTime) < time_ticks(request.preferredStartTime) or
                time_ticks(candidate.endTime) > time_ticks(request.preferredEndTime)
            ):
                raise ValueError("Candidate outside preferred times")


class SlotMatch(SchedulingContract):
    slotId: EntityId
    explanationSummary: str = Field(min_length=1, max_length=300)


class SchedulingRanking(SchedulingContract):
    rankedSlots: list[SlotMatch] = Field(min_length=1, max_length=5)


class ProposedSlot(SchedulingContract):
    # Phase 1 shape. All fields except the constrained explanation come from ASP.NET.
    studioId: EntityId
    packageId: EntityId
    date: date
    startTime: LocalTime
    endTime: LocalTime
    explanationSummary: str = Field(min_length=1, max_length=300)
    evidenceIds: list[EvidenceId] = Field(min_length=1, max_length=50)


class SchedulingOutput(SchedulingContract):
    rankedSlots: list[ProposedSlot] = Field(min_length=1, max_length=5)
    unmetPreferences: list[str]
    # Internal trusted ASP.NET snapshots, never populated from the ranking model.
    backendEvidence: list[SchedulingCandidateResponse] = Field(default_factory=list, max_length=5)
