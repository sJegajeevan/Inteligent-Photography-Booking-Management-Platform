# Agentic AI Phase 1: contracts and deterministic backend services

No agent/provider runtime, new HTTP endpoints, workflow tables or client UI are
implemented in this phase. Contracts are ordinary C# types outside EF Models;
ApplicationDbContext and existing migrations are unchanged by this work.

## Contracts

`Contracts/AgenticAi/CustomerPhotographyRequirements.cs` defines a versioned
customer requirement with photography type, location, LKR budget, date range,
optional paired time preferences, coverage, requested services and notes.
Identity comes from ASP.NET claims, not this payload. Precise customer GPS is
excluded. Currency/timezone are explicitly LKR/Asia/Colombo; no FX conversion is
implied. Date-relative validation must use a backend-controlled clock.

`Contracts/AgenticAi/RecommendationContracts.cs` defines:

- StudioMatchingOutput: ranked IDs, concise explanations, evidence references.
- PackageRecommendationOutput: studio/package IDs and existing customization DTO.
- SchedulingOutput: proposed dates/times and evidence references.
- ValidationSafetyOutput: outcome, structured findings and check timestamp.
- RecommendationSelection/RecommendationCheck: read-only backend check input
  and authoritative pricing/validation evidence.
- FinalRecommendationProposal: server-issued identity/version, requirements,
  selection, pricing, validation and expiry. Human approval is required; it is
  explicitly not a reservation.

Agent output contracts represent **untrusted suggestions**, not authority.
Future orchestration must enforce nested schemas, bounded collection sizes,
nonempty/eligible IDs, evidence provenance and requirements compatibility.
ASP.NET must assemble the final proposal; never bind model-supplied pricing or
approval claims as trusted data. Explanations are short user-facing summaries,
not chain-of-thought. No chain-of-thought field/storage is added.

## Services and preserved behavior

- StudioDiscoveryService extracts normal/nearby search, service filtering,
  public studio services and published availability from PublicStudiosController.
  Reuses DistanceService. Retains nullable coordinate behavior, radius limits,
  distance sorting and public DTOs. HTTP image origin resolution remains in the
  controller; shared sanitization prevents exposing filesystem paths.
- BookingSlotRules is the single source for date/time, availability containment,
  half-open overlap predicate, active conflict statuses, package-duration and
  booking-total checks.
- BookingSlotValidationService offers a read-only point-in-time slot check.
  An internal overload accepts the availability row already locked by booking
  creation. It preserves duplicate-customer and general-conflict responses.
  Public results contain no other customer's booking IDs/details.
- RecommendationValidationService validates input/customization, active package
  ownership, duration, slot eligibility and authoritative price. It composes
  existing PhotographyPackageService and PackagePriceCalculationService. It
  has no write methods. This is booking-selection eligibility, not the future
  semantic Safety Agent or a complete requirements-matching validator.
- BookingsController retains JWT/role/ownership checks, studio FOR UPDATE,
  availability FOR SHARE, transaction boundaries, history and notifications.
  Active package lookup now reuses GetPublicAsync. The pricing algorithm is
  unchanged; its pure calculator is internal so the check project can test it.

Availability listings remain published windows, not free-slot listings. A
successful read-only check does not lock/reserve a slot. Actual booking creation
must recheck under the existing locks. `today` is supplied by trusted backend
code; the existing controller's server-local date behavior is preserved. Define
one authoritative business clock/timezone before future tool endpoints accept
date requirements. There are no AI booking create/update tools or endpoints.

## Verification

The repository already uses an executable check project instead of a unit-test
framework. Phase1Checks follows that pattern, references the API project and
exits nonzero on failure. It is run with `dotnet run`, not `dotnet test`.

From repository root:

```powershell
dotnet build backend/PhotographyBooking.Api -o backend/PhotographyBooking.Api/bin/phase1-verification
dotnet run --project backend/tests/Phase1Checks -p:OutputPath=bin/phase1-verification/
dotnet run --project backend/tests/LocationChecks
```

Results: build succeeded with 0 warnings/errors; 74 Phase 1 checks passed;
18 existing location checks passed. Ordinary `dotnet build` was attempted but
the existing running API locked its default apphost output; the separate
output directory avoided stopping that process.

Checks cover search combinations, safe public images, nullable-coordinate
normal browsing, invalid nearby parameters, time/availability boundaries,
terminal versus active statuses, back-to-back/overlapping slots, studio/date
isolation, duration, price breakdown/add-ons/overflow, requirement/selection
validation and JSON contracts. Npgsql query translation is checked using
ToQueryString; no connection is opened. This is not a live PostgreSQL
concurrency or HTTP integration test.

## Files changed in Phase 1

New (relative to backend/PhotographyBooking.Api):

- Contracts/AgenticAi/CustomerPhotographyRequirements.cs
- Contracts/AgenticAi/RecommendationContracts.cs
- Services/StudioDiscoveryService.cs
- Services/BookingSlotRules.cs
- Services/BookingSlotValidationService.cs
- Services/RecommendationValidationService.cs
- Properties/AssemblyInfo.cs (test assembly access to internal pure helpers)

Updated:

- Controllers/PublicStudiosController.cs
- Controllers/BookingsController.cs
- Services/PackagePriceCalculationService.cs (calculator visibility only)
- Program.cs (dependency injection registrations)

Also added: backend/tests/Phase1Checks/Phase1Checks.csproj,
backend/tests/Phase1Checks/Program.cs and this document.

## Phase 2 prerequisites

Implement authorized, bounded tool adapters; backend-controlled time; full
cross-contract/requirements validation; cancellation through existing package
and pricing queries; durable workflow state/auditing; authenticated orchestration
and versioned human approval. Schema changes require a separately authorized
deployment. Python, FastAPI, LangGraph, Gemini and React/Flutter AI UI remain
unimplemented. Add isolated PostgreSQL integration/concurrency tests when a
disposable test database is authorized.

DATABASE CHANGED: NO

MIGRATIONS RUN: NO

AI PROVIDER CALLED: NO

No commits or pushes made.
