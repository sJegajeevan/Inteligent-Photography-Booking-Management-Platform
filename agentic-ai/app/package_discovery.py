"""Fixed-route ASP.NET reads, including the read-only pricing POST."""
import asyncio

import httpx
from pydantic import TypeAdapter, ValidationError

from app.config import Settings
from app.package_contracts import PackageCustomization, PackageQuote, PublicPackage, validate_id


class PackageDiscoveryFailure(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class PackageDiscoveryTool:
    def __init__(self, settings: Settings, *, transport: httpx.AsyncBaseTransport | None = None):
        self.settings = settings
        self.transport = transport

    @staticmethod
    def _id(value: str) -> str:
        try:
            return validate_id(value)
        except (ValueError, TypeError, AttributeError):
            raise PackageDiscoveryFailure("invalid_package_reference") from None

    async def _read(self, studio_id: str, package_id: str | None = None,
                    customization: PackageCustomization | None = None) -> bytes:
        # This private helper also enforces the allow-list; it accepts no URL,
        # caller-supplied path, HTTP method or arbitrary request body.
        path = f"/api/public/studios/{self._id(studio_id)}/packages"
        method, body = "GET", None
        if package_id is not None:
            if customization is None:
                raise PackageDiscoveryFailure("invalid_package_reference")
            path += f"/{self._id(package_id)}/calculate-price"
            method, body = "POST", customization.model_dump(mode="json")
        try:
            async with asyncio.timeout(self.settings.aspnet_timeout_seconds):
                async with httpx.AsyncClient(
                    base_url=str(self.settings.aspnet_api_base_url),
                    timeout=self.settings.aspnet_timeout_seconds, follow_redirects=False,
                    trust_env=False, transport=self.transport,
                ) as client:
                    async with client.stream(method, path, json=body) as response:
                        if response.status_code != 200:
                            raise PackageDiscoveryFailure("backend_unavailable")
                        data = bytearray()
                        async for chunk in response.aiter_bytes():
                            data.extend(chunk)
                            if len(data) > 1_000_000:
                                raise PackageDiscoveryFailure("invalid_backend_response")
                        return bytes(data)
        except (TimeoutError, httpx.TimeoutException):
            raise PackageDiscoveryFailure("backend_timeout") from None
        except httpx.HTTPError:
            raise PackageDiscoveryFailure("backend_unavailable") from None

    async def packages(self, studio_id: str) -> list[PublicPackage]:
        raw = await self._read(studio_id)
        try:
            packages = TypeAdapter(list[PublicPackage]).validate_json(raw, strict=True)
        except ValidationError:
            raise PackageDiscoveryFailure("invalid_backend_response") from None
        if len(packages) > 2000 or len({p.id.lower() for p in packages}) != len(packages):
            raise PackageDiscoveryFailure("invalid_backend_response")
        for package in packages:
            if (package.studioId != studio_id or
                len({s.id.lower() for s in package.services}) != len(package.services) or
                len({a.id.lower() for a in package.addons}) != len(package.addons) or
                any(a.packageId != package.id for a in package.addons)):
                raise PackageDiscoveryFailure("invalid_backend_response")
        return packages

    async def quote(self, studio_id: str, package_id: str,
                    customization: PackageCustomization) -> PackageQuote:
        raw = await self._read(studio_id, package_id, customization)
        try:
            quote = PackageQuote.model_validate_json(raw)
        except ValidationError:
            raise PackageDiscoveryFailure("invalid_backend_response") from None
        if (quote.packageId != package_id or
            [addon.id for addon in quote.selectedAddons] != customization.selectedAddonIds or
            quote.extraHours != customization.extraHours or
            quote.additionalPhotographers != customization.additionalPhotographers):
            raise PackageDiscoveryFailure("invalid_backend_response")
        # finalPrice is ASP.NET's authority. Never rebuild it from components.
        return quote
