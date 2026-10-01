"""Grounded ranking: model ordering and evidence-backed, constrained explanations."""
import asyncio
import json

from pydantic import ValidationError

from app.llm import GeminiService
from app.matching_contracts import StudioMatchingInput, StudioMatchingOutput, StudioRanking
from app.studio_discovery import StudioDiscoveryTool
from app.package_discovery import PackageDiscoveryTool, PackageDiscoveryFailure
from app.package_eligibility import eligible_packages


class MatchingFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class StudioMatchingAgent:
    def __init__(self, discovery: StudioDiscoveryTool, llm: GeminiService, packages: PackageDiscoveryTool | None = None):
        self.discovery = discovery
        self.llm = llm
        self.packages = packages or PackageDiscoveryTool(discovery.settings, transport=discovery.transport)

    async def match(self, request: StudioMatchingInput) -> StudioMatchingOutput:
        studios = await self.discovery.discover(request)
        requirements = request.requirements
        candidates = [s for s in studios if
                      {"all", requirements.photographyType.strip().casefold()} &
                      {t.strip().casefold() for t in s.photographyTypes}]
        # The endpoint is not paginated; consider every matching result so the
        # model chooses the best three across the full authoritative candidate set.
        # Feasibility is read-only and does not execute PackageRecommendation.
        # Bound all studio package/quote reads together, not one timeout per studio.
        feasible = []
        try:
            async with asyncio.timeout(self.discovery.settings.aspnet_timeout_seconds):
                for studio in candidates:
                    if await eligible_packages(self.packages, requirements, [studio.id]):
                        feasible.append(studio)
        except TimeoutError:
            raise PackageDiscoveryFailure("backend_timeout") from None
        candidates = feasible
        target_count = min(3, len(candidates))
        caveats = [
            "At least one active package has a qualifying backend quote; prices will be checked again after selection.",
            "Requested dates, times and coverage have not been checked for availability.",
        ]
        if requirements.requestedServices:
            caveats.append("Requested services require package-level verification.")
        if requirements.minimumBudget is not None:
            caveats.append("Minimum budget requires a package quote.")
        if requirements.notes:
            caveats.append("Additional notes have not been verified.")
        if not candidates:
            return StudioMatchingOutput(rankedStudios=[], unmetPreferences=caveats)

        reasons = {}
        for studio in candidates:
            type_reason = ("Supports all photography types" if
                           "all" in {t.strip().casefold() for t in studio.photographyTypes}
                           else "Lists the requested photography type")
            allowed = [f"{type_reason} and has an active package with a qualifying backend quote."
                       if type_reason == "Supports all photography types" else
                       "Lists the requested photography type and has an active package with a qualifying backend quote."]
            if request.nearby and request.nearby.radiusKm is not None:
                allowed.append(f"{type_reason} and is within the requested search radius.")
            reasons[studio.id] = allowed
        # No precise customer GPS, notes or descriptive prompt-injection surface
        # is sent to Gemini. Facts are only the backend snapshot and requirements.
        payload = json.dumps({
            "targetCount": target_count,
            "requirements": requirements.model_dump(mode="json", exclude={"notes"}),
            "candidates": [{
                "studioId": s.id, "photographyTypes": s.photographyTypes,
                "startingPrice": str(s.startingPrice), "distanceKm": s.distanceKm,
                "allowedReasons": reasons[s.id],
            } for s in candidates],
        })
        raw = await self.llm.rank_studios(payload)
        try:
            if not isinstance(raw, str) or len(raw) > 16000:
                raise MatchingFailure("malformed_structured_output")
            ranking = StudioRanking.model_validate_json(raw)
        except ValidationError:
            raise MatchingFailure("malformed_structured_output") from None
        seen = set()
        for match in ranking.rankedStudios:
            if match.studioId not in reasons:
                raise MatchingFailure("unknown_studio_id")
            if match.studioId in seen:
                raise MatchingFailure("duplicate_studio_id")
            seen.add(match.studioId)
            if match.explanationSummary not in reasons[match.studioId]:
                raise MatchingFailure("unsupported_recommendation_claim")
        if len(ranking.rankedStudios) != target_count:
            raise MatchingFailure("malformed_structured_output")
        return StudioMatchingOutput(rankedStudios=ranking.rankedStudios, unmetPreferences=caveats)
