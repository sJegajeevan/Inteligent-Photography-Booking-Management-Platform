"""Grounded ranking: model ordering and evidence-backed, constrained explanations."""
import json

from pydantic import ValidationError

from app.llm import GeminiService
from app.matching_contracts import StudioMatchingInput, StudioMatchingOutput, StudioRanking
from app.studio_discovery import StudioDiscoveryTool


class MatchingFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class StudioMatchingAgent:
    def __init__(self, discovery: StudioDiscoveryTool, llm: GeminiService):
        self.discovery = discovery
        self.llm = llm

    async def match(self, request: StudioMatchingInput) -> StudioMatchingOutput:
        studios = await self.discovery.discover(request)
        requirements = request.requirements
        candidates = [s for s in studios if
                      {"all", requirements.photographyType.strip().casefold()} &
                      {t.strip().casefold() for t in s.photographyTypes} and
                      s.startingPrice <= requirements.maximumBudget]
        # The endpoint is not paginated. Bound Gemini input deterministically;
        # nearby candidates preserve backend DistanceService ordering.
        truncated = len(candidates) > 50
        candidates = candidates[:50]
        caveats = [
            "Starting prices are not package quotes; final budget fit is unverified.",
            "Requested dates, times and coverage have not been checked for availability.",
        ]
        if requirements.requestedServices:
            caveats.append("Requested services require package-level verification.")
        if requirements.minimumBudget is not None:
            caveats.append("Minimum budget requires a package quote.")
        if requirements.notes:
            caveats.append("Additional notes have not been verified.")
        if truncated:
            caveats.append("Ranking is limited to the first 50 eligible backend results.")
        if not candidates:
            return StudioMatchingOutput(rankedStudios=[], unmetPreferences=caveats)

        reasons = {}
        for studio in candidates:
            type_reason = ("Supports all photography types" if
                           "all" in {t.strip().casefold() for t in studio.photographyTypes}
                           else "Lists the requested photography type")
            allowed = [f"{type_reason} and lists a starting price within the maximum budget."
                       if type_reason == "Supports all photography types" else
                       "Lists the requested photography type and a starting price within the maximum budget."]
            if request.nearby and request.nearby.radiusKm is not None:
                allowed.append(f"{type_reason} and is within the requested search radius.")
            reasons[studio.id] = allowed
        # No precise customer GPS, notes or descriptive prompt-injection surface
        # is sent to Gemini. Facts are only the backend snapshot and requirements.
        payload = json.dumps({
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
        return StudioMatchingOutput(rankedStudios=ranking.rankedStudios, unmetPreferences=caveats)
