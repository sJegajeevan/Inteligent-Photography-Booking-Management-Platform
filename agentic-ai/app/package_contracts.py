"""Strict Phase 4.2 wire contracts. Generated rankings never contain pricing."""
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, ConfigDict, Field

from app.matching_contracts import Contract, Money


def validate_id(value: str) -> str:
    parsed = UUID(value)
    if not parsed.int or str(parsed) != value.lower():
        raise ValueError("Expected a nonempty hyphenated UUID")
    return value  # Preserve authoritative spelling for exact-reference checks.


EntityId = Annotated[str, AfterValidator(validate_id)]


class PackageContract(Contract):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True)


class IncludedService(PackageContract):
    id: EntityId
    serviceName: str
    description: str


class PackageAddon(PackageContract):
    id: EntityId
    packageId: EntityId
    name: str
    description: str
    price: Money
    createdAt: datetime
    updatedAt: datetime


class PublicPackage(PackageContract):
    id: EntityId
    studioId: EntityId
    name: str
    description: str
    basePrice: Money
    extraHourRate: Money
    additionalPhotographerRate: Money
    durationHours: Decimal = Field(gt=0, allow_inf_nan=False)
    numberOfPhotographers: int = Field(ge=1)
    editedPhotoCount: int = Field(ge=0)
    albumIncluded: bool
    videoIncluded: bool
    coverImageUrl: str
    status: Literal["Active"]
    createdAt: datetime
    updatedAt: datetime
    services: list[IncludedService]
    addons: list[PackageAddon]


class PackageCustomization(PackageContract):
    selectedAddonIds: list[EntityId] = Field(default_factory=list, max_length=0)
    extraHours: int = Field(ge=0, le=1000)
    additionalPhotographers: Literal[0] = 0


class SelectedAddon(PackageContract):
    id: EntityId
    name: str
    price: Money


class PackageQuote(PackageContract):
    packageId: EntityId
    packageName: str
    basePrice: Money
    selectedAddons: list[SelectedAddon]
    extraHours: int = Field(ge=0, le=1000)
    extraHoursCost: Money
    additionalPhotographers: int = Field(ge=0, le=100)
    additionalPhotographersCost: Money
    finalPrice: Money


class PackageMatch(PackageContract):
    studioId: EntityId
    packageId: EntityId
    explanationSummary: str = Field(min_length=1, max_length=300)


class PackageRanking(PackageContract):
    rankedPackages: list[PackageMatch] = Field(min_length=1, max_length=5)


class PackageRecommendation(PackageMatch):
    customization: PackageCustomization
    pricing: PackageQuote


class PackageRecommendationOutput(PackageContract):
    rankedPackages: list[PackageRecommendation] = Field(min_length=1, max_length=5)
    unmetPreferences: list[str]
