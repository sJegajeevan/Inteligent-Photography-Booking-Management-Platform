"""Phase 1 camelCase wire contracts; GPS is transient invocation context only."""
from datetime import date, time
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)


Money = Annotated[Decimal, Field(ge=0, le=Decimal("9999999999999999.99"), allow_inf_nan=False)]
ServiceName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]


class CustomerPhotographyRequirements(Contract):
    schemaVersion: Literal[1] = 1
    photographyType: str = Field(min_length=1, max_length=100)
    location: str = Field(min_length=1, max_length=500)
    minimumBudget: Money | None = None
    maximumBudget: Money
    currency: Literal["LKR"] = "LKR"
    timeZoneId: Literal["Asia/Colombo"] = "Asia/Colombo"
    earliestDate: date
    latestDate: date
    preferredStartTime: time | None = None
    preferredEndTime: time | None = None
    coverageHours: Decimal = Field(ge=Decimal("0.01"), le=24, allow_inf_nan=False)
    requestedServices: list[ServiceName] = Field(max_length=20)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("photographyType", "location")
    @classmethod
    def not_blank(cls, value):
        if not value.strip():
            raise ValueError("blank requirement")
        return value.strip()

    @model_validator(mode="after")
    def ordered(self):
        if self.minimumBudget is not None and self.minimumBudget > self.maximumBudget:
            raise ValueError("budget range")
        if self.earliestDate == date.min or self.latestDate < self.earliestDate:
            raise ValueError("date range")
        start, end = self.preferredStartTime, self.preferredEndTime
        if (start is None) != (end is None):
            raise ValueError("paired times required")
        if start is not None and (start.tzinfo or end.tzinfo or start >= end):
            raise ValueError("ordered local times required")
        return self


class NearbySearch(Contract):
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    radiusKm: float | None = Field(default=None, gt=0, le=500, allow_inf_nan=False)


class StudioMatchingInput(Contract):
    requirements: CustomerPhotographyRequirements
    nearby: NearbySearch | None = None


class StudioSummary(Contract):
    id: str
    studioName: str
    location: str
    descriptionSummary: str
    photographyTypes: list[str]
    startingPrice: Money
    distanceKm: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    profileImageUrl: str | None = None
    coverImageUrl: str | None = None

    @field_validator("id")
    @classmethod
    def authoritative_id(cls, value):
        if UUID(value).int == 0:
            raise ValueError("empty studio ID")
        return value  # Preserve exact backend spelling, never normalize model IDs.


class StudioMatch(Contract):
    studioId: str = Field(min_length=1, max_length=36)
    explanationSummary: str = Field(min_length=1, max_length=300)


class StudioRanking(Contract):
    rankedStudios: list[StudioMatch] = Field(min_length=1, max_length=5)


class StudioMatchingOutput(Contract):
    rankedStudios: list[StudioMatch] = Field(max_length=5)
    unmetPreferences: list[str]
