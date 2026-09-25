"""Deterministic eligibility and backend quotes precede constrained AI ranking."""
import asyncio
import json
from math import ceil

from pydantic import ValidationError

from app.llm import GeminiService
from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import (
    PackageCustomization, PackageRanking, PackageRecommendation,
    PackageRecommendationOutput, validate_id,
)
from app.package_discovery import PackageDiscoveryFailure, PackageDiscoveryTool


class PackageFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class PackageRecommendationAgent:
    MAX_CANDIDATES = 50

    def __init__(self, discovery: PackageDiscoveryTool, llm: GeminiService):
        self.discovery = discovery
        self.llm = llm

    async def recommend(self, requirements: CustomerPhotographyRequirements,
                        studios: StudioMatchingOutput) -> PackageRecommendationOutput:
        try:
            studio_ids = [validate_id(s.studioId) for s in studios.rankedStudios]
            if not studio_ids or len(studio_ids) > 5 or len(set(s.lower() for s in studio_ids)) != len(studio_ids):
                raise ValueError("Invalid ranked studios")
        except (ValueError, TypeError, AttributeError):
            raise PackageFailure("invalid_package_input") from None
        requested = {name.strip().casefold() for name in requirements.requestedServices}
        candidates = {}
        try:
            # Total deadline covers all package and quote requests, not just each
            # individual call. Serial requests keep request volume predictable.
            async with asyncio.timeout(self.discovery.settings.aspnet_timeout_seconds):
                packages = []
                for studio_id in studio_ids:
                    packages.extend(await self.discovery.packages(studio_id))
                if len({p.id.lower() for p in packages}) != len(packages):
                    raise PackageDiscoveryFailure("invalid_backend_response")
                if not packages:
                    raise PackageFailure("no_packages")
                eligible = [p for p in packages if requested <=
                            {s.serviceName.strip().casefold() for s in p.services}]
                if len(eligible) > self.MAX_CANDIDATES:
                    # Fail explicitly rather than silently omit potentially
                    # affordable packages or claim an exhaustive best match.
                    raise PackageFailure("package_candidate_limit_exceeded")
                for package in eligible:
                    customization = PackageCustomization(
                        extraHours=max(0, ceil(requirements.coverageHours - package.durationHours)))
                    quote = await self.discovery.quote(package.studioId, package.id, customization)
                    if quote.finalPrice > requirements.maximumBudget:
                        continue
                    if requirements.minimumBudget is not None and quote.finalPrice < requirements.minimumBudget:
                        continue
                    reasons = ["The backend quote for the selected customization is within the requested budget."]
                    if requested:
                        reasons.append("Includes every requested service and the backend quote is within the requested budget.")
                    reasons.append("Package duration plus the selected extra hours covers the requested coverage hours.")
                    candidates[(package.studioId, package.id)] = (package, customization, quote, reasons)
        except TimeoutError:
            raise PackageDiscoveryFailure("backend_timeout") from None
        if not candidates:
            raise PackageFailure("no_matching_packages")

        payload = json.dumps({
            "requirements": requirements.model_dump(mode="json", include={
                "photographyType", "coverageHours", "requestedServices", "minimumBudget",
                "maximumBudget", "currency",
            }),
            "candidates": [{
                "studioId": p.studioId, "packageId": p.id, "name": p.name,
                "durationHours": str(p.durationHours),
                "services": [s.model_dump(mode="json") for s in p.services],
                "customization": customization.model_dump(mode="json"),
                "pricing": quote.model_dump(mode="json"), "allowedReasons": reasons,
            } for p, customization, quote, reasons in candidates.values()],
        })
        raw = await self.llm.rank_packages(payload)
        try:
            if not isinstance(raw, str) or len(raw) > 16000:
                raise PackageFailure("invalid_gemini_output")
            ranking = PackageRanking.model_validate_json(raw)
        except ValidationError:
            raise PackageFailure("invalid_gemini_output") from None
        recommendations, seen = [], set()
        for match in ranking.rankedPackages:
            if (match.studioId, match.packageId) not in candidates:
                raise PackageFailure("unknown_package_reference")
            if match.packageId in seen:
                raise PackageFailure("duplicate_package_id")
            seen.add(match.packageId)
            _, customization, quote, reasons = candidates[(match.studioId, match.packageId)]
            if match.explanationSummary not in reasons:
                raise PackageFailure("unsupported_recommendation_claim")
            recommendations.append(PackageRecommendation(
                **match.model_dump(), customization=customization, pricing=quote))
        caveats = [
            "Quotes are point-in-time LKR prices, not reservations or availability checks.",
            "Extra hours round any coverage shortfall up to a whole purchased hour.",
            "No paid add-ons or additional photographers have been selected.",
            "Requested dates and preferred times remain unverified.",
        ]
        if requirements.notes:
            caveats.append("Additional notes have not been verified.")
        return PackageRecommendationOutput(rankedPackages=recommendations, unmetPreferences=caveats)
