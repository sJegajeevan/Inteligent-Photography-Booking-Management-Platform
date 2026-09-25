"""Typed read-only adapter. No caller/model-supplied URLs, paths or HTTP verbs."""
import asyncio

import httpx
from pydantic import TypeAdapter, ValidationError

from app.config import Settings
from app.matching_contracts import StudioMatchingInput, StudioSummary


class DiscoveryFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class StudioDiscoveryTool:
    def __init__(self, settings: Settings, *, transport: httpx.AsyncBaseTransport | None = None):
        self.settings = settings
        self.transport = transport

    async def discover(self, request: StudioMatchingInput) -> list[StudioSummary]:
        # Search narrows by backend location; exact photography eligibility is
        # checked against photographyTypes after retrieval (search is fuzzy).
        path = "/api/public/studios"
        params = {"location": request.requirements.location}
        if request.nearby is not None:
            path += "/nearby"
            params.update(request.nearby.model_dump(exclude_none=True))
        try:
            async with asyncio.timeout(self.settings.aspnet_timeout_seconds):
                async with httpx.AsyncClient(
                    base_url=str(self.settings.aspnet_api_base_url),
                    timeout=self.settings.aspnet_timeout_seconds,
                    follow_redirects=False, trust_env=False, transport=self.transport,
                ) as client:
                    async with client.stream("GET", path, params=params) as response:
                        if response.status_code != 200:
                            raise DiscoveryFailure("backend_unavailable")
                        body = bytearray()
                        async for chunk in response.aiter_bytes():
                            body.extend(chunk)
                            if len(body) > 1_000_000:
                                raise DiscoveryFailure("invalid_backend_response")
            studios = TypeAdapter(list[StudioSummary]).validate_json(bytes(body), strict=True)
            if len(studios) > 2000 or len({s.id for s in studios}) != len(studios):
                raise DiscoveryFailure("invalid_backend_response")
            # Nearby distances must come from ASP.NET DistanceService.
            if request.nearby and any(
                s.distanceKm is None or
                (request.nearby.radiusKm is not None and s.distanceKm > request.nearby.radiusKm)
                for s in studios
            ):
                raise DiscoveryFailure("invalid_backend_response")
            return studios
        except (TimeoutError, httpx.TimeoutException):
            raise DiscoveryFailure("backend_timeout") from None
        except httpx.HTTPError:
            raise DiscoveryFailure("backend_unavailable") from None
        except (ValidationError, ValueError):
            raise DiscoveryFailure("invalid_backend_response") from None
