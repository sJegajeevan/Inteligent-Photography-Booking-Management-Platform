"""Shared package eligibility using ASP.NET package reads and authoritative quotes.

No price arithmetic or model calls. Both matching stages use this same policy.
"""
import asyncio
from math import ceil

from app.package_contracts import PackageCustomization
from app.package_discovery import PackageDiscoveryFailure


async def eligible_packages(discovery, requirements, studio_ids, *, require_packages=False):
    requested = {name.strip().casefold() for name in requirements.requestedServices}
    candidates = {}
    try:
        # Total deadline covers all package and quote requests, not just each
        # individual call. Serial requests keep request volume predictable.
        async with asyncio.timeout(discovery.settings.aspnet_timeout_seconds):
            packages = []
            for studio_id in studio_ids:
                packages.extend(await discovery.packages(studio_id))
            if len({p.id.lower() for p in packages}) != len(packages):
                raise PackageDiscoveryFailure("invalid_backend_response")
            if not packages and require_packages:
                raise PackageDiscoveryFailure("no_packages")
            eligible = [p for p in packages if requested <=
                        {s.serviceName.strip().casefold() for s in p.services}]
            # Discovery bounds each studio to 2,000 packages / 1 MB. Evaluate
            # every service-compatible package under the shared deadline;
            # ranking shortlists must be formed only after authoritative quotes.
            for package in eligible:
                customization = PackageCustomization(
                    extraHours=max(0, ceil(requirements.coverageHours - package.durationHours)))
                if package.durationHours + customization.extraHours > 24:
                    continue
                quote = await discovery.quote(package.studioId, package.id, customization)
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
    return candidates
