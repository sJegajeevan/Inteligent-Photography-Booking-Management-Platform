# SnapSync staged AI journey — implementation report

## 1. Architecture

The customer API now runs one genuine agent stage per action. Initial creation runs Studio Matching and returns persisted choices. Studio, package, and schedule selections respectively trigger Package Recommendation, Scheduling, and Validation. A successful validation creates a canonical customer draft; only an explicit submission enters `AwaitingApproval`.

ASP.NET owns identity, durable state, selection checks, pricing, availability, canonical publication, and approval. Python receives bounded invocation context and runs one existing LangGraph agent node. No transaction spans a Python call.

## 2. ASP.NET files and endpoints

Added:

- `backend/PhotographyBooking.Api/Services/AiJourneyService.cs`: ownership, stage claims, authoritative option checks, execution, completion, retry, draft creation, and submission.
- `backend/PhotographyBooking.Api/Services/JourneyState.cs`: append-only JourneyV1 events and deterministic state reconstruction.
- `backend/PhotographyBooking.Api/Contracts/AgenticAi/JourneyContracts.cs`: bounded customer commands and display projections.

Updated `AiWorkflowsController.cs`, `WorkflowApiContracts.cs`, `InternalPythonWorkflowClient.cs`, `AiWorkflowService.cs`, and DI registration in `Program.cs`.

| Endpoint | Behavior |
| --- | --- |
| `POST /api/ai-workflows` | Normalize requirements, create/resume using `operationId`, execute Studio Matching only |
| `GET /api/ai-workflows/{id}` | Read/resume the customer's persisted journey; existing role-scoped read for reviewers |
| `POST /api/ai-workflows/{id}/journey/studio` | Select a persisted studio option; run Package Recommendation |
| `POST /api/ai-workflows/{id}/journey/package` | Select a package from that studio; run Scheduling |
| `POST /api/ai-workflows/{id}/journey/schedule` | Select a persisted valid slot; run Validation |
| `POST /api/ai-workflows/{id}/journey/retry` | Retry the failed stage, or renew expired validation |
| `POST /api/ai-workflows/{id}/journey/submit` | Freshly check a validated draft and send it for studio approval |

Action bodies contain `operationId`, expected `revision`, and (for selections) `optionEventId`. Prices, customer identity, validation outcomes, and completion flags are not customer commands. Existing list, approve, and reject endpoints remain.

## 3. FastAPI / LangGraph

Added `agentic-ai/app/journey.py` and registered its authenticated internal endpoint:

`POST /internal/ai-workflows/{workflow_id}/stage`

`build_workflow(..., stage=...)` compiles a graph containing exactly the requested existing agent node. Prerequisites require a single selected studio, then a single package belonging to it, then a single selected schedule. Existing Studio Matching, Package Recommendation, Scheduling, and Validation agents remain intact. Existing full-workflow code remains available for compatibility tests but is not the customer creation path.

The adapter checks the internal token, input size, duplicate JSON properties, stage prerequisites, timeout, and response size. Operational failures return safe codes. Python has no PostgreSQL dependency or persistence path.

## 4. JourneyV1 persistence

Uses only the existing `AiWorkflows` aggregate and `AiWorkflowEvents`. JourneyV1 events store started/result/completed/selected/validated/failed/rewound state, monotonically ordered sequence numbers, revisions, operation IDs, and source/option references. Options contain authoritative IDs and only the bounded price, duration, schedule, and safe summary fields allowed by the deployed contract.

Display metadata is hydrated from current studio/package data. No complete studio/package records, raw Gemini payloads, chain-of-thought, credentials, or tokens are persisted.

Submission is an append-only `JourneySubmittedForApproval` audit event in the same existing event store; its event ID provides submission replay protection. It has no details payload and does not require another constraint or persistence mechanism.

The existing proposal constraint and guard require a nonzero proposal version to retain canonical JSON. Consequently, invalidating an already validated draft retains its historical canonical snapshot until a new validated version replaces it. That snapshot is hidden from the active customer proposal and cannot be approved while the workflow is in a draft/execution state. Active selections come from JourneyV1 events; canonical selection columns remain canonical-proposal pointers.

## 5. Flutter screens and UX

Added `lib/screens/ai/ai_journey_view.dart`; integrated it through `ai_workflow_screens.dart`, the workflow model, and service.

- Requirements: progress chips and **Find Studios with AI**.
- Studio: available cover images, studio name, location, specialties, bounded recommendation reason, **View Studio**, and selection.
- Package: selected studio summary; only that studio's options, authoritative quote, package duration, extra hours, and included services.
- Schedule: selected studio/package summary and real dated slot cards in Sri Lanka time.
- Validation: canonical price and successful deterministic checks, then **Send for Studio Approval**.
- Submitted: **Awaiting Studio Approval**; approved journeys retain navigation to My Bookings.

Progress comes from persisted state and active requests. Each stage has loading and retry behavior. Duplicate actions are disabled, uncertain outcomes require refresh, and navigation to an earlier stage does not execute an agent until the customer selects an option. Opening history fetches the full saved journey, including validated drafts that have not been submitted.

## 6. React studio review

Updated `AiWorkflowView.jsx` to show Customer Requirements → Selected Studio → Selected Package → Selected Schedule → Validation Passed (only when the canonical validation passed). Preserved the single final Approve/Reject pair and existing request bodies. Added a rendered-summary regression test.

## 7. Invalidation

Selecting a studio clears package, schedule, and validation results/selections. Selecting a package clears schedule and validation. Selecting a schedule clears validation. Each action advances the journey revision. Earlier valid option sets remain available for deliberate reselection; downstream sets are regenerated, never silently reused.

Stage results can commit only if their operation still owns the active claim. Late results from abandoned operations cannot overwrite a newer revision.

## 8. Security, ownership, and replay

Every customer action checks authenticated claims against the authoritative Customer account and workflow ownership. Selection references must belong to the current workflow's retained option set. Studios, active package ownership, current quotes, duration, requested services, and candidate schedules are checked server-side.

EF's existing `xmin` concurrency token fences every stage claim/completion, including forced workflow updates when appending events. Event appends and state updates commit atomically. Replaying creation, selection, or submission does not rerun the operation. Conflicting/stale actions return a safe conflict.

A running claim blocks other work. After four minutes an interrupted operation can be retried explicitly; this is crash recovery, not simulated agent progress. Draft workflows have a 24-hour working lifetime. Canonical proposals retain the existing five-minute evidence lifetime.

## 9. Verification results

No live database or Gemini calls were made by these checks.

| Command / suite | Result |
| --- | --- |
| ASP.NET build | Passed, 0 warnings / 0 errors |
| `dotnet run --project backend/tests/Phase1Checks --no-restore` | 1,007 checks passed: 45 staged journey; 160 Python transport/execution; 217 workflow API/service; 60 canonical publication/approval; 74 foundational; 91 scheduling; 34 scheduling endpoints; 200 final validation; 126 final validation endpoints |
| `dotnet run --project backend/tests/AiJourneyChecks --no-restore` | 187 offline constraint/model checks passed |
| Python `pytest -q` | 639 passed; 2 dependency deprecation warnings |
| React `npm test` | 34 passed |
| React `npm run build` | Passed |
| React `npm run lint` | Passed |
| Flutter full `flutter test --no-pub` | 112 passed |
| Final focused Flutter journey/workflow/polish rerun | 50 passed after the final display changes |
| Flutter `flutter analyze --no-pub` | No issues found |
| Flutter `flutter build web --no-pub` | Passed; web output built and Wasm dry run succeeded |

Journey tests cover stage ordering, missing prerequisites, valid/foreign options, authoritative price changes after agent validation, ownership, draft submission guards, revision invalidation, failures/retries, in-flight replay, interrupted-stage recovery, late completion rejection, EF event insertion, and idempotent submission. Flutter covers each staged screen, selection, loading, failure, navigation, narrow-screen layout, and existing features. Approval foundation tests retain the existing deterministic revalidation coverage.

## 10. Database/schema

No SQL was executed. No migration was created or run. No database update, constraint edit, table/column change, or schema modification was performed. The deployed JourneyV1 SQL, constraint source, historical deployment SQL, and pre-existing database/model edits were left as supplied.

## 11. Remaining manual integration tests

These require the running application, real provider, and live data and were deliberately not performed under the instruction prohibiting SQL execution:

1. Restart ASP.NET and FastAPI together and run the updated Flutter client; use their existing configured internal token and backend URLs. No `.env` edits were made.
2. Exercise the entire flow with real future studio availability; confirm each selection produces only its next agent request.
3. Close/reopen after every stage, change each upstream selection, and verify the visible options and persisted progress.
4. Use two customer sessions to verify live ownership isolation; use concurrent requests to verify PostgreSQL `xmin` conflicts and late-result fencing end-to-end.
5. Change a studio's price/availability through existing management screens between recommendation, submission, and owner approval. Verify rejection/revalidation and no premature booking.
6. Approve the final proposal as its studio owner. Verify exactly one Pending Booking after fresh deterministic revalidation; exercise rejection and replay.
7. Check real image URLs, small-device layouts, View Studio, Google Maps, WhatsApp, and booking messaging on the target devices.

## 12–15. Preserved guarantees

- No fake agents, arbitrary progress timers, or precomputed four-stage results masquerading as staged execution.
- Gemini ranks/recommends; authoritative prices, ownership, availability, conflicts, and final validity remain in ASP.NET/PostgreSQL.
- No booking is created by matching, selection, validation, or customer submission. The existing owner approval + fresh locked revalidation + Pending Booking path is unchanged.
- WhatsApp and booking messaging implementation files were preserved; their Flutter/React regressions passed as part of the suites above. Manual browsing, authentication, admin, reviews, Maps, studio/package management, and ordinary booking implementations were not changed for this task.

All prior uncommitted work was preserved. No `.env` modification, commit, or push was performed.
