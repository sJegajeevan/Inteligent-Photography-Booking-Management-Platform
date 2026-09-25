# Human Approval Wiring Step 3

Customer clients call ASP.NET only. POST /api/ai-workflows verifies the JWT and
database Customer role, normalizes requirements, and commits the Submitted workflow
and event before executing Python. HTTP 201 returns the sanitized durable workflow
DTO, including its final status even when execution fails. GET, Studio review,
approve, and reject retain their existing authorization and response contracts.

## Configuration

Python reads INTERNAL_WORKFLOW_TOKEN from environment configuration or its existing
ignored .env. ASP.NET reads the same variable from its process environment. Supply
a random secret of 32–512 printable ASCII characters without spaces. Neither service
writes or returns it. Example files contain empty placeholders only. The integration
client disables HTTP logging, redirects, cookies, and proxy inheritance. No existing
local .env or secret was changed.

ASP.NET reads AI_WORKFLOW_PYTHON_BASE_URL, an HTTP(S) origin without credentials,
path, query, or fragment, and AI_WORKFLOW_TIMEOUT_SECONDS (default 150, range 1–180).
Python uses WORKFLOW_TIMEOUT_SECONDS (default 120, maximum 180). Configure Python's
deadline below ASP.NET's. Missing or invalid client configuration produces a durable
Failed workflow without dispatch. backend/.env.example documents process variables;
ASP.NET does not load that file.

Keep FastAPI on loopback locally, or on a private service network with TLS across
hosts. No deployment or live service configuration was performed in this step.

## Internal boundary

POST /internal/ai-workflows/{workflowId}/run requires X-Internal-Token, checked before
reading the request. Authentication failures return fixed 401 JSON; invalid or extra
fields return fixed 400 JSON; bodies above 16 KiB return 413. Input contains
executionId, normalized requirements, and optionally existing transient nearby
context. The public ASP.NET submission contract does not introduce GPS input.
CustomerId, proposal versions, reviewers, decisions, URLs, and tool configuration
cannot be supplied to Python.

The existing graph runs Submitted → StudioMatching → PackageRecommendation →
Scheduling → Validation → provisional AwaitingApproval. Completion contains
workflow/execution correlation, requirements, terminal status, final deterministic
evidence, and only the selected candidate's retained scheduling evidence. No proposal,
prompts, model explanations, raw events, exceptions, credentials, or approval authority
are returned. Decimal wire values retain Pydantic's exact decimal strings; .NET reads
them as decimal and checks field shape, constants, correlation, and evidence consistency.
Responses are capped at 64 KiB on both sides.

## Persistence and failure behavior

ASP.NET claims Submitted → StudioMatching in a short transaction disposed before
the bounded synchronous Python call. No database transaction or lock spans AI
execution. There is no background task or execution HTTP retry.

On Pass, ASP.NET transitions to Validation and calls AiWorkflowPublicationService.
Stored requirements and expected initial version zero come from ASP.NET. Publication
locks and reloads the workflow, freshly checks backend data, constructs the canonical
proposal, allocates version one, and atomically commits AwaitingApproval / HumanApproval
and its event. Approval still freshly revalidates later; execution never approves or books.

Python Failed, unavailable, unauthorized, timeout, and malformed responses produce
Failed plus a fixed audit event/code and no proposal. RevalidationRequired and
NeedsInput remain those statuses without publication evidence. Fresh publication
checks can independently produce RevalidationRequired when evidence changes. Request
cancellation propagates after a bounded, awaited five-second attempt to mark an
in-progress execution Failed.

Claiming requires Submitted, version zero, and no proposal. Replaying execution for
an already claimed workflow does not run Python or republish. Publication retains
its locked version precondition and xmin safeguards. Separate Customer POSTs are
separate workflows: this step adds no idempotency-key API or recovery worker.
Process termination or unavailable database cleanup can leave an in-progress row
for future operational recovery; it cannot fabricate success or a reservation.

## Verification

Tests use offline ASGI requests, mocked graph dependencies/HTTP transports, SQL
translation, and in-memory persistence boundaries. A Python endpoint completion is
shared as a .NET contract fixture. Canonical fresh validation is real in orchestration
tests; database locking/persistence is reviewed in source, not exercised live.
There are no Gemini calls, live database writes, migrations, or bookings in testing.
Build output uses temporary directories and leaves the running API process untouched.
