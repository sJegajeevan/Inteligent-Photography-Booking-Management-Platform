"""Deterministic eligibility and backend quotes precede constrained AI ranking."""
import json

from pydantic import ValidationError

from app.llm import GeminiService
from app.matching_contracts import CustomerPhotographyRequirements, StudioMatchingOutput
from app.package_contracts import (
    PackageRanking, PackageRecommendation,
    PackageRecommendationOutput, validate_id,
)
from app.package_discovery import PackageDiscoveryTool
from app.package_eligibility import eligible_packages


class PackageFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class PackageRecommendationAgent:
    MAX_RANKING_CANDIDATES = 50

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
        candidates = await eligible_packages(self.discovery, requirements, studio_ids, require_packages=True)
        if not candidates:
            raise PackageFailure("no_matching_packages")
        target_count = min(3, len(candidates))
        shortlisted = len(candidates) > self.MAX_RANKING_CANDIDATES
        if shortlisted:
            # All candidates have passed authoritative eligibility. Bound Gemini
            # input by affordability, with stable IDs breaking equal-price ties.
            # Validate its output against this exact supplied shortlist as well.
            candidates = dict(sorted(candidates.items(), key=lambda item: (
                item[1][2].finalPrice, item[0][0], item[0][1]
            ))[:self.MAX_RANKING_CANDIDATES])

        payload = json.dumps({
            "targetCount": target_count,
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
        if len(recommendations) != target_count:
            raise PackageFailure("invalid_gemini_output")
        caveats = [
            "Quotes are point-in-time LKR prices, not reservations or availability checks.",
            "Extra hours round any coverage shortfall up to a whole purchased hour.",
            "No paid add-ons or additional photographers have been selected.",
            "Requested dates and preferred times remain unverified.",
        ]
        if requirements.notes:
            caveats.append("Additional notes have not been verified.")
        if shortlisted:
            caveats.append("AI ranking considers the 50 lowest-priced eligible backend quotes; equal prices are ordered by studio and package ID.")
        return PackageRecommendationOutput(rankedPackages=recommendations, unmetPreferences=caveats)
