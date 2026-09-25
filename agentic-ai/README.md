# SnapSync Agentic AI — Phase 4.2 Package Recommendation

Private FastAPI + LangGraph + Gemini with Studio Matching, Package Recommendation,
Scheduling, and deterministic Validation/Safety. Human Approval Step 3 exposes an
authenticated internal execution adapter; ASP.NET owns durable canonical publication.
See [Step 3 configuration and behavior](../docs/human-approval-step-3.md).

Architecture: Flutter / React → ASP.NET Core → private FastAPI → LangGraph → Gemini.
Python has no database driver, SQL tool, booking-write tool or arbitrary HTTP tool.

## Setup and configuration

From the repository root (PowerShell):

```powershell
Set-Location agentic-ai
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8001
```

Use the existing private ignored `.env` or a process secret manager. Never put
real API keys into source or command history. Phase 4.2 does not modify `.env`.

| Variable | Meaning |
| --- | --- |
| GEMINI_API_KEY | Private Gemini Developer API key |
| GEMINI_MODEL | Explicit model ID available to your account |
| ASPNET_API_BASE_URL | Trusted HTTP(S) backend origin; default http://localhost:5000; local live backend may use http://localhost:5284 |
| ASPNET_TIMEOUT_SECONDS | Default 10, maximum 60; bounds each request and the entire package retrieval/quote phase |
| AI_TIMEOUT_SECONDS | Deadline per Gemini attempt; default 10, maximum 60; existing local configuration may set 30 |
| AI_MAX_ATTEMPTS | Provider attempts, default 2, maximum 3 |

Every Gemini attempt creates and closes its own async client and has its own
deadline. Transient HTTP 408/429/500/502/503/504, transport failures and timeouts
may retry; other provider errors and validation failures do not. SDK internal
retries are disabled. Backoff is 0.25 seconds before attempt 2 and, when configured,
0.5 seconds before attempt 3. With a 30-second timeout and two attempts, allow
approximately 60.25 seconds plus cancellation/cleanup scheduling overhead per
Gemini operation. Attempts remain capped by AI_MAX_ATTEMPTS. External cancellation
propagates and does not trigger retries. Agent output validation remains outside
the retry boundary; malformed model output is never regenerated as a fallback.

The backend origin cannot include credentials, a path, query or fragment. Adapter
redirects and environment proxy inheritance are disabled. No new dependencies.

`GET /health` is liveness only. `GET /health/ai` performs a Gemini metadata probe,
not a generation or workflow test. No unauthenticated execution endpoint has
been added. The local runner below executes the same graph wired by create_app;
authenticated ASP.NET-to-FastAPI orchestration uses the internal Step 3 endpoint.

## Read-only ASP.NET tools

Studio Matching retains its existing discovery adapter:

- `GET /api/public/studios?location=...`
- `GET /api/public/studios/nearby?location=...&latitude=...&longitude=...&radiusKm=...`

Phase 4.2 adds only these fixed routes:

- `GET /api/public/studios/{studioId}/packages`
- `POST /api/public/studios/{studioId}/packages/{packageId}/calculate-price`

The POST performs a read-only calculation through PackagePriceCalculationService;
it does not create a quote row, workflow row or booking. Both routes are public
under current backend authorization configuration. Studio management endpoints
are never used. All path parameters must be nonempty hyphenated UUIDs.

The adapter validates complete public package DTOs, including active status,
studio ownership, duplicate package/service/add-on IDs, add-on ownership, finite
nonnegative pricing fields and positive duration. Backend arrays are limited to
2,000 packages per response and bodies to 1 MB. Package IDs must also be unique
across the selected studios. All backend calls are bounded; a partial failed
fetch/quote fails the stage rather than presenting incomplete evidence as success.

## Input and eligibility

The input is unchanged: existing CustomerPhotographyRequirements plus optional
transient nearby search context. Precise GPS never enters persisted graph state.
Package Recommendation accepts only the validated ranked studios from Phase 4.1
(at most five), and fetches packages for those IDs only.

Every requested service must occur in the package's own included services using
trimmed, case-insensitive exact matching. No synonyms, description-based inference,
or studio-wide inclusion inference is performed. An empty requested-services
list imposes no service restriction. Studio Matching's photography-type `All`
wildcard remains unchanged; it is not a service-name wildcard.

For every eligible package, orchestration builds exactly one customization:

```text
selectedAddonIds = []
additionalPhotographers = 0
extraHours = max(0, ceil(coverageHours - durationHours))
```

This calculates a coverage quantity, not a price. Coverage is purchased in whole
extra hours, so fractional shortfalls round upward. Invalid/nonpositive package
duration fails backend-response validation. Notes do not cause paid add-ons or
additional photographers to be selected. Packages are not ranked as available on
a date: scheduling and preferred-time feasibility remain unverified.

At most 50 service-eligible packages may be quoted/ranked. Above that limit the
stage fails explicitly with package_candidate_limit_exceeded before quoting;
it does not silently truncate or claim an exhaustive best match. Requests are
serial and share the total backend deadline; large/slow catalogs may time out.

## Pricing authority and budget

ASP.NET alone calculates:

```text
FinalPrice = resolved BasePrice
           + selected add-on prices
           + ExtraHours × ExtraHourRate
           + AdditionalPhotographers × AdditionalPhotographerRate
```

Existing backend legacy base-price/name fallback remains authoritative. Python
never reconstructs the total from components. It verifies that the quote's
packageId, selected add-ons, extraHours and additionalPhotographers match the
requested customization, then compares the returned Decimal finalPrice to:

```text
finalPrice <= maximumBudget
minimumBudget <= finalPrice   (when minimumBudget is supplied)
```

No extras are added merely to satisfy a minimum budget. Quote failure never
falls back to local pricing. The requirements contract specifies LKR; the current
pricing response has no currency/expiry fields. Quotes are point-in-time evidence,
not reservations, availability checks or full booking validation.

## Gemini and deterministic validation

Both ranking methods use response_mime_type="application/json" and
response_json_schema=<RankingModel>.model_json_schema(). The legacy response_schema
transport is not used. All new Pydantic contracts are strict with extra="forbid".

Gemini receives only service-eligible, budget-eligible, authoritatively quoted
candidates. The package prompt includes IDs, names, included services, duration,
predetermined customization, backend pricing evidence and allowed explanations.
Backend descriptive text is untrusted data. Customer notes, location/GPS and
credentials are excluded. Gemini has no callable tools.

Its entire output is restricted to:

```json
{
  "rankedPackages": [
    {
      "studioId": "exact supplied UUID",
      "packageId": "exact supplied UUID",
      "explanationSummary": "exact candidate-specific allowed sentence"
    }
  ]
}
```

Python strictly reparses output, checks collection limits, exact supplied ID
pairs, duplicate package IDs, forbidden fields and allowed explanations. Unknown
studios/packages, mismatched pairs, invented prices/services/add-ons, malformed
output, and unsupported availability or other claims reject the entire response.
There is no permissive fallback parser. Arbitrary model prose is not accepted.

Only after successful validation does orchestration attach customization and
pricing from the trusted candidate snapshot. The returned package_recommendation
contains rankedPackages with those attachments plus deterministic unmetPreferences
caveats. No model-supplied price or customization is trusted. This is a stage result,
not a FinalRecommendationProposal; no server-issued evidence IDs are fabricated.

## Graph and audit

```text
Submitted → StudioMatching → PackageRecommendation → Scheduling placeholder → END
Any implemented-stage failure → Failed → END
```

Successful production execution returns:

```text
status = Scheduling
blocked_stage = Scheduling
error_code = scheduling_agent_not_implemented
```

Scheduling does not generate dates or fake completion. Validation/Safety and
approval are not executed. A package failure has status=Failed and
blocked_stage=PackageRecommendation; studio results remain present but no package
recommendations are accepted.

The workflow preserves StudioMatchingCompleted and appends
PackageRecommendationCompleted or PackageRecommendationFailed. Events contain
fixed summaries, stage, success, durationMs, and a safe errorCode on failure.
Events carry no prompts, secrets, GPS, exception bodies or hidden reasoning.
They remain in memory: ASP.NET must own future durable audit transport, identities
and timestamps. No database/checkpointer is introduced.

create_app always injects both real agents. For isolated Phase 4.1 callers/tests,
build_workflow(studio_agent) without a package agent retains the previous explicit
package_agent_not_implemented boundary. This compatibility path is not used by
the production app or manual runner.

## Failure codes

| Condition | Code |
| --- | --- |
| Backend non-200, redirect or transport failure | backend_unavailable |
| Backend request or total package-fetch/quote deadline | backend_timeout |
| Malformed/oversized package or mismatched quote | invalid_backend_response |
| Malformed UUID passed to adapter | invalid_package_reference |
| Invalid/empty/duplicate ranked studio input | invalid_package_input |
| No packages returned from selected studios | no_packages |
| No service/budget eligible quoted candidates | no_matching_packages |
| More than 50 service-eligible packages | package_candidate_limit_exceeded |
| Gemini configuration missing | gemini_not_configured |
| Gemini deadline exceeded | gemini_timeout |
| Gemini provider error | gemini_unavailable |
| Malformed/empty/extra-field package output | invalid_gemini_output |
| Unknown or mismatched studio/package reference | unknown_package_reference |
| Duplicate ranked package | duplicate_package_id |
| Unsupported explanation | unsupported_recommendation_claim |

No eligible candidates means no package Gemini call. Phase 4.1 may already have
called Gemini to rank studios before the package stage discovers no packages.

## Automated verification

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests
```

Latest verification, including per-attempt retry handling: **212 passed, 0 failed**, with two upstream
deprecation warnings (Google Gen AI typing and Starlette/AnyIO). External calls
are mocked. Tests exercise the real SDK serialization via mock HTTP, full app
progression, provider 400/503 and retry behavior, deadlines, malformed output,
quote binding, service matching, coverage, budgets and privacy. Existing Studio
Matching regression tests are unchanged and pass. tests/test_llm_retries.py covers
fresh attempt deadlines, bounded retries, safe errors, per-attempt cleanup and
external cancellation without retry.

No live Gemini calls, backend builds, migrations or live database changes were
performed for implementation verification.

## Exact manual LIVE verification

Use the already-running ASP.NET API and the existing private Gemini configuration.
From the repository root:

```powershell
Set-Location agentic-ai
.\.venv\Scripts\python.exe -m app.match_studios .\examples\studio-matching.json
```

If already inside agentic-ai, run only the second command. The command performs
real backend reads and Gemini generation; it writes no bookings or workflow rows.
Exit code 0 means the Scheduling boundary was reached, not that scheduling or
an entire booking recommendation workflow completed.

Before running, confirm the example's selected studios have active packages whose
included service names match every requested service and whose backend quote fits
the requested budgets. Read-only inspection for the known studio is available at:

```powershell
Invoke-RestMethod 'http://localhost:5284/api/public/studios/fa245b2d-5fa0-4255-91ee-783b21a9911f/packages'
```

Do not create or alter live data merely to make this test pass. If the live catalog
has no eligible packages, no_packages or no_matching_packages is the correct safe
result. On success, inspect package_recommendation.rankedPackages, customization,
pricing.finalPrice and both successful stage events. Compare pricing with the
same read-only calculate-price request if needed. Prices, dates and catalog data
can change; this run does not reserve anything.

## Files in Phase 4.2

Created: app/package_contracts.py, app/package_discovery.py,
app/package_recommendation.py, tests/test_package_recommendation.py,
tests/test_package_ranking_transport.py.

Modified: app/llm.py, app/workflow.py, app/main.py, app/match_studios.py,
tests/test_foundation.py, README.md.

Studio Matching implementation/contracts/tests, ASP.NET, React, Flutter, database
schema/migrations, dependencies and .env remain untouched by this phase.

DATABASE CHANGED: NO

MIGRATIONS RUN: NO

BACKEND CHANGED: NO

No direct Python database access, booking writes, commits or pushes.
