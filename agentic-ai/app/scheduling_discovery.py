"""One allow-listed ASP.NET read-only scheduling search. No generic HTTP tool."""
import asyncio

import httpx
from pydantic import ValidationError

from app.config import Settings
from app.matching_contracts import CustomerPhotographyRequirements
from app.package_contracts import PackageCustomization, validate_id
from app.scheduling_contracts import SchedulingCandidateRequest, SchedulingCandidateResponse


class SchedulingDiscoveryFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class SchedulingDiscoveryTool:
    def __init__(self, settings: Settings, *, transport: httpx.AsyncBaseTransport | None = None):
        self.settings = settings
        self.transport = transport

    async def discover(self, studio_id: str, package_id: str,
                       requirements: CustomerPhotographyRequirements,
                       customization: PackageCustomization) -> SchedulingCandidateResponse:
        try:
            studio_id, package_id = validate_id(studio_id), validate_id(package_id)
            request = SchedulingCandidateRequest.from_requirements(requirements, customization)
        except (ValidationError, ValueError, TypeError, AttributeError):
            raise SchedulingDiscoveryFailure("invalid_scheduling_input") from None
        path = f"/api/public/studios/{studio_id}/packages/{package_id}/available-slots"
        try:
            async with asyncio.timeout(self.settings.aspnet_timeout_seconds):
                async with httpx.AsyncClient(
                    base_url=str(self.settings.aspnet_api_base_url),
                    timeout=self.settings.aspnet_timeout_seconds, follow_redirects=False,
                    trust_env=False, transport=self.transport,
                ) as client:
                    async with client.stream("POST", path, json=request.model_dump(mode="json")) as response:
                        if response.status_code == 400:
                            raise SchedulingDiscoveryFailure("invalid_scheduling_input")
                        if response.status_code == 404:
                            raise SchedulingDiscoveryFailure("package_unavailable")
                        if response.status_code != 200:
                            raise SchedulingDiscoveryFailure("backend_unavailable")
                        raw = bytearray()
                        async for chunk in response.aiter_bytes():
                            raw.extend(chunk)
                            if len(raw) > 1_000_000:
                                raise SchedulingDiscoveryFailure("invalid_backend_response")
            result = SchedulingCandidateResponse.model_validate_json(bytes(raw), strict=True)
            result.validate_for(studio_id, package_id, request)
            return result
        except (TimeoutError, httpx.TimeoutException):
            raise SchedulingDiscoveryFailure("backend_timeout") from None
        except httpx.HTTPError:
            raise SchedulingDiscoveryFailure("backend_unavailable") from None
        except (ValidationError, ValueError):
            raise SchedulingDiscoveryFailure("invalid_backend_response") from None
