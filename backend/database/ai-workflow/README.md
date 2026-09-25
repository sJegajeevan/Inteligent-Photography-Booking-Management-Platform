# Phase 2 AI workflow persistence — PREPARED, NOT APPLIED

**STOP: deployment requires separate explicit authorization.** No database was
connected to or changed during preparation. Do not run `dotnet ef database update`,
re-enable archived migrations, or call `EnsureCreated`/`Migrate` at startup.
Do not exercise the new persistence service against the current database until
this additive schema change has been reviewed and deployed.

## Exact proposed change

Create only these three tables in `public`:

- `AiWorkflows`: UUID ID; required Customer FK; status; normalized requirements
  JSONB; current step; nullable final proposal JSONB; proposal version; optional
  selected Studio/Package FKs; UTC created/updated/expiry timestamps.
- `AiWorkflowEvents`: UUID ID; Workflow FK; bounded event type, step and sanitized
  summary; optional allow-listed operational details JSONB; success flag;
  optional nonnegative millisecond duration; UTC timestamp.
- `AiWorkflowApprovals`: UUID ID; Workflow FK; positive proposal version;
  reviewer User FK; Approved/Rejected/RevisionRequested decision; optional bounded
  human reason; UTC timestamp; immutable proposal snapshot JSONB. The snapshot
  preserves the exact proposal reviewed after subsequent revisions.

Three primary keys, six foreign keys, twelve CHECK constraints and seven indexes
are included. No existing table/column is altered, no rows are backfilled, no
extension is installed, and no migration-history entry is created. No Booking
relationship or automatic Booking action is introduced. Npgsql maps `RowVersion`
to PostgreSQL's existing `xmin` system column; SQL adds no RowVersion/xmin column.

Relationships use RESTRICT deletion, including Customer/Reviewer references and
Workflow event/approval references, to prevent cascading loss of ownership/audit
evidence. Existing deletion of a referenced studio/package/user may therefore
require a separately designed retention/archive process after workflows exist.

## Status and decision design

The intended normal sequence is Submitted -> StudioMatching ->
PackageRecommendation -> Scheduling -> Validation -> AwaitingApproval ->
Approved/Rejected. Also supported: NeedsInput, Failed, Cancelled, Expired and
RevalidationRequired. SQL enforces valid status values, not the future graph's
complete transition policy. RevisionRequested records a decision and moves the
workflow to RevalidationRequired. A newly published revision must have a higher
proposal version and receive its own decision.

`AiWorkflowApprovalService` is registered for future authenticated HTTP adapters;
no endpoint is added. It verifies authentication plus current database role,
permits the selected studio's owner or an Admin, checks status/expiry/version,
and verifies package-to-studio membership. It uses a workflow row lock, studio
ownership lock, xmin optimistic concurrency and the unique (WorkflowId,
ProposalVersion) index. Status, approval snapshot and templated audit event are
saved in one transaction. Expired, stale, repeat and unauthorized decisions are
rejected. Repeated identical decisions are rejected, not replayed as success.
Future adapters must map database concurrency/unique conflicts to a safe response.

The service approves a **recommendation**, never a reservation or booking.
Fresh slot/pricing validation before presenting or acting on a result still uses
Phase 1's read-only services; this phase does not implement orchestration or
automatically create a booking on approval.

The EF persistence guard makes workflow CustomerId immutable, prevents proposal
version rollback and same-version edits to published proposal/requirements/
selection, and rejects tracked updates/deletes of events or approvals. Revised
content cannot retain Approved/Rejected status. Privileged SQL and EF bulk
update/delete bypass tracked guards: future tools must use the guarded services,
and runtime database grants should exclude audit UPDATE/DELETE privileges.

The FKs enforce existing IDs, not User.Role or Package.StudioId relationships.
Customer creation must obtain identity from authenticated ASP.NET claims and
verify the Customer role in the future submission endpoint; it must never bind
CustomerId directly from customer/model input. The approval service enforces
reviewer roles, selected-studio ownership and package membership. No customer
submission/query endpoint is introduced here.

## Audit/privacy

Requirements/proposal writers must serialize the validated Phase 1
CustomerPhotographyRequirements/FinalRecommendationProposal contracts. JSONB
CHECKs verify object structure, not the full contract or semantic safety. Future
writers must validate schema, model suggestions, proposal version/IDs and remove
secrets/precise GPS before persistence. Do not store raw Gemini prompts/responses,
chain-of-thought, API keys, exception dumps or auth headers.

Event details permit only `proposalVersion`, `errorCode` and `attempt` keys.
Approval audit summaries come from fixed templates; human reasons are stored
only in the bounded approval field, not copied into general execution logs.
Event UUID primary keys also allow future publishers to reuse a stable event ID
for duplicate detection. No raw model transcript or reasoning storage is added.

## Indexes and checks

- Workflow customer + creation time: customer history.
- Workflow status + expiry: pending/expiry scans.
- Selected studio + status + updated time: studio approval queue.
- Selected package: FK lookups.
- Event workflow + creation time + ID: ordered history with deterministic ties.
- Unique approval workflow + proposal version: one decision per version.
- Approval reviewer + creation time: reviewer audit history.

CHECKs bound status/step/decision values, JSON object shape, event detail keys,
nonnegative duration, positive approval version, proposal presence/version/
selected references, approval-ready proposal presence and timestamp ordering.
No generic JSONB GIN index is added without a demonstrated query need.

## Review artifacts and offline verification

`AiWorkflowSchemaChange.cs` is the dedicated **review-only schema delta**, compiled
only by `backend/tools/AiWorkflowPreparation`. It compares the current EF model
with that same model excluding the three AI entities; it permits only these
three CreateTable operations and their indexes. Any existing-table change stops
generation. This is not a migration appended to the historical chain.

`20260921000200_ai_workflow.sql` is the Npgsql-generated, reviewable deployment
artifact. It wraps creation in a transaction with five-second lock and thirty-
second statement timeouts. It checks existing principal table/ID types and
refuses to proceed if an AI table already exists. FK creation further validates
principal keys. Failure rolls back the transaction; partial/reapplied schema
must be reconciled separately, never skipped with IF NOT EXISTS.

From repository root (all offline, no settings/secrets/API host loaded):

```powershell
dotnet build backend/PhotographyBooking.Api -o backend/PhotographyBooking.Api/bin/phase2-verification
dotnet run --project backend/tools/AiWorkflowPreparation -p:OutputPath=bin/phase2-verification/ -- --verify backend/database/ai-workflow/20260921000200_ai_workflow.sql
dotnet run --project backend/tests/Phase1Checks -p:OutputPath=bin/phase2-verification/
dotnet run --project backend/tests/LocationChecks
```

Generation uses the same preparation command with `--generate` instead of
`--verify`. It writes a local SQL file only. A connection interceptor rejects
every database connection attempt. There is no apply mode.

Results: backend build 0 warnings/errors; 55 Phase 2 offline/model checks;
74 Phase 1 checks; 18 location checks, all passed. Tests cover model mappings,
schema-delta scope, SQL equality, statuses, uniqueness, required ownership,
concurrency, version/expiry guards, append-only history and Phase 1 JSON
roundtrip. Live SQL execution, database constraints and concurrent requests have
not been integration-tested because database execution is outside this task.

## Deployment awaiting approval

1. Review `preflight.sql` against the intended target using read-only access;
   inspect principal PKs, types, ownership columns and absence of AI tables.
   The file is prepared but has not been executed.
2. Arrange backup and a deployment window; confirm application/DB role grants
   and retention implications. Record the reviewed SQL SHA-256.
3. **Only after explicit authorization**, apply the complete reviewed
   `20260921000200_ai_workflow.sql` with stop-on-error behavior, without invoking
   historical EF migrations. Do not deploy a workflow consumer before the tables.
4. Inspect `verify.sql` results against the generated definitions and indexes.
   Run rollback-only transaction/concurrency/authorization integration checks
   against an approved disposable environment before exposing approval endpoints.

No automated Down/drop script is provided: once used, dropping these tables
would destroy approval/audit history and requires a separate retention decision.

## Files changed

API: new Models/AiWorkflow.cs, AiWorkflowEvent.cs, AiWorkflowApproval.cs;
Data/AiWorkflowConfiguration.cs, AiWorkflowPersistenceGuard.cs;
Services/AiWorkflowApprovalService.cs; updated Data/ApplicationDbContext.cs and
Program.cs. Preparation: backend/tools/AiWorkflowPreparation/{Program.cs,
AiWorkflowPreparation.csproj}. Review package: this README, AiWorkflowSchemaChange.cs,
20260921000200_ai_workflow.sql, preflight.sql, verify.sql.

DATABASE CHANGED: NO

MIGRATIONS RUN: NO

GEMINI CALLED: NO

No Gemini/LangGraph/FastAPI/React/Flutter implementation, commits or pushes.
