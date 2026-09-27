# AI stabilization verification — 2026-09-27

## Architecture inspected

The existing `agentic-ai/app/main.py` constructs FastAPI and all four agents. `workflow.py`
assembles the LangGraph state machine: StudioMatching → PackageRecommendation → Scheduling
→ Validation → AwaitingApproval. No second implementation was created.

- `studio_matching.py` / `studio_discovery.py`: ASP.NET studio discovery, deterministic eligibility,
  constrained Gemini ordering and explanations using only supplied studio IDs.
- `package_recommendation.py` / `package_discovery.py`: existing active packages, requested services,
  backend customization quotes, budget filtering, then constrained ranking.
- `scheduling.py` / `scheduling_discovery.py`: backend availability/overlap checks and Asia/Colombo
  candidate times; the model can rank supplied slot IDs only.
- `validation.py` / `validation_discovery.py`: deterministic backend final revalidation; no LLM.
- `llm.py`: existing bounded retries (1–3 configured attempts), per-attempt timeout, exponential
  backoff with jitter, and allow-listed logging. Retry and permanent-failure cases were tested.
- `internal_execution.py`: authenticated `POST /internal/ai-workflows/{id}/run`.
  FastAPI also exposes `/health` and `/health/ai`.
- ASP.NET: `InternalPythonWorkflowClient`, `AiWorkflowExecutionService`,
  `AiWorkflowPublicationService`, `CanonicalProposalService`, `AiWorkflowApprovalService` and
  `AiWorkflowService` handle transport, persistence, publication, review and booking creation.
- Existing PostgreSQL entities: `AiWorkflow`, append-only `AiWorkflowEvent` and
  `AiWorkflowApproval`; proposal JSON/version, unique workflow/version decisions, and xmin concurrency.
- User endpoints: `/api/ai-workflows`, `/{id}`, `/{id}/approve`, `/{id}/reject`.

## Findings and fixes

1. HTTP 200 from FastAPI means the execution envelope was delivered; its workflow status may
   still be Failed. Specific graph error codes were collapsed to `execution_failed` before .NET
   persistence. The envelope now carries an allow-listed code and failing stage. .NET persists
   safe stage/code/message and returns a sanitized `failure` object for failed workflows.
2. Approval compared JSON expiry ticks with PostgreSQL timestamps using exact equality.
   PostgreSQL truncates sub-microsecond precision. Approval now permits only differences under
   one microsecond, matching the existing read behavior; larger mismatches remain rejected.
3. Initial publication already correctly generates proposal version 1 from server-owned version 0.
   Tests verify persistence, fresh approval and stale-version rejection; this logic was retained.
4. Approval previously recorded a decision without creating a booking. It now locks the workflow,
   studio and availability, revalidates canonical evidence, runs existing slot/duration/pricing
   rules, and atomically writes the booking, history, notification, approval and workflow event.
   ReadCommitted and the same studio lock used by normal booking creation prevent overlapping
   approval writes. A duplicate decision remains rejected rather than creating a second booking.
5. Approval UI text was corrected. Created bookings use the existing initial Pending status;
   approving an AI recommendation does not mark a shoot Completed.

## Executed verification

- Full Python suite: **598 passed**, two third-party deprecation warnings.
- .NET Phase1Checks: **962 passed**: 160 Python execution, 217 workflow API/service,
  60 publication/approval, 74 foundation, 91 scheduling, 34 scheduling endpoint,
  200 final validation and 126 final validation endpoint checks.
- Live PostgreSQL/.NET/FastAPI integration: **35 passed**.
- Booking completion checks: **40 passed** (ephemeral SQLite).
- Location checks: **18 passed**.
- Total .NET checks including integration: **1,055 passed**.
- React configured test suite: **28 passed**; Vite production build passed.
- Focused Flutter AI suite: **18 passed**, after updating the obsolete no-booking text assertion.
- ASP.NET API build: passed, **0 warnings / 0 errors**, separate output folder.
- FastAPI startup, `/health`, internal authentication rejection, and authenticated .NET → FastAPI
  → .NET application-data calls were executed over real loopback HTTP.

The live harness exercised all four real agents, real discovery/pricing/availability/validation
endpoints, real canonical publication and real PostgreSQL approval/booking persistence. Only
Gemini ranking was replaced by a test-only constrained ranking fixture. It proved:

- Fresh version-1 proposal approval creates exactly one real Pending booking.
- Booking ownership, authoritative price, time range, status history and notification are saved.
- No booking exists before approval, after rejection, or when revalidation fails.
- Stale proposal, unauthorized owner and duplicate approval are rejected.
- Two overlapping proposals approved concurrently create only one booking; the other requires revalidation.
- A test-only database constraint forces a failure AFTER booking insertion. Booking, history,
  notification, approval, booking event and workflow state all roll back. Retrying after removing
  the test constraint creates one booking.
- Specific failure diagnostics survive PostgreSQL persistence and a subsequent API read.

## Isolation and reproduction

`AiWorkflowLiveChecks.cs` only connects to a dedicated loopback PostgreSQL cluster on port 55439,
user `ai_test`. It generates a unique `ai_checks_<guid>` database, creates the EF model there,
and drops that database in `finally`. It does not load application connection strings, apply
application migrations or change existing data. The test-only constraint is confined to that database.
FastAPI runs on loopback port 55441 with generated internal credentials, no `.env`, and no Gemini key.
The Python subprocess is stopped in `finally`. The dedicated PostgreSQL cluster was stopped after testing.

From the repository root, with that dedicated test cluster running:

```powershell
dotnet build backend/tests/Phase1Checks/Phase1Checks.csproj --no-restore --output backend/tests/Phase1Checks/bin/AiAudit
dotnet backend/tests/Phase1Checks/bin/AiAudit/Phase1Checks.dll
dotnet backend/tests/Phase1Checks/bin/AiAudit/Phase1Checks.dll --ai-live-checks
```

## Files changed for this AI task

Pre-existing uncommitted work was retained. This list excludes earlier booking/review UI tasks
and files already modified by others that were only inspected.

```text
agentic-ai/app/internal_execution.py
agentic-ai/tests/test_internal_execution.py
agentic-ai/tests/integration_app.py
agentic-ai/VERIFICATION.md
backend/PhotographyBooking.Api/Contracts/AgenticAi/PythonExecutionContracts.cs
backend/PhotographyBooking.Api/Contracts/AgenticAi/WorkflowApiContracts.cs
backend/PhotographyBooking.Api/Services/AiExecutionFailure.cs
backend/PhotographyBooking.Api/Services/AiWorkflowApprovalService.cs
backend/PhotographyBooking.Api/Services/AiWorkflowExecutionService.cs
backend/PhotographyBooking.Api/Services/AiWorkflowService.cs
backend/PhotographyBooking.Api/Services/CanonicalProposalService.cs
backend/PhotographyBooking.Api/Services/InternalPythonWorkflowClient.cs
backend/tests/Phase1Checks/AiWorkflowLiveChecks.cs
backend/tests/Phase1Checks/Program.cs
backend/tests/Phase1Checks/ProposalPublicationChecks.cs
frontend/photography-web/src/pages/Studio/AiWorkflowView.jsx
frontend/photography-web/src/pages/Studio/StudioAiWorkflows.jsx
frontend/photography-web/tests/ai-workflows.test.mjs
mobile/photography_mobile/lib/screens/ai/ai_workflow_screens.dart
mobile/photography_mobile/test/ai_workflow_test.dart
```

## Limits

Live Gemini availability and recommendation quality were not verified. Its retry/error behavior
was tested with simulated provider responses. Google Maps was not called and is not required
for this location-string workflow. Production deployment and real customer/studio data were
not exercised. Existing five-minute evidence/proposal expiry remains enforced. Existing Approved
workflows created before this change are not backfilled into bookings.
