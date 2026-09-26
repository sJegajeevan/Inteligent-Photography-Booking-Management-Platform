# ADR 004: AI Workflow Persistence and Database Strategy

## Status
Accepted

## Context
SnapSync AI uses a multi-step Agentic AI workflow consisting of Studio Matching, Package Recommendation, Scheduling, Validation, and Human Approval.

The workflow may take multiple steps and can fail, require additional input, wait for human approval, or be rejected.

Therefore, the system needs durable workflow state instead of keeping AI workflow information only in Python memory.

The ASP.NET Core backend and PostgreSQL database are the authoritative parts of the system. The Python Agentic AI service must not directly access or modify the application database.

## Decision
Persist the canonical AI workflow state in PostgreSQL through the ASP.NET Core backend.

Three main entities are used:

- `AiWorkflows`
- `AiWorkflowEvents`
- `AiWorkflowApprovals`

Python FastAPI and LangGraph perform AI orchestration but do not directly access PostgreSQL.

The architecture is:

Customer Client
→ ASP.NET Core
→ PostgreSQL
→ Internal FastAPI/LangGraph
→ ASP.NET Core
→ PostgreSQL
→ Human Review

## AiWorkflows
`AiWorkflows` stores the current durable state of each AI recommendation workflow.

It includes information such as:

- Workflow identifier
- Customer ownership
- Current workflow status
- Current workflow step
- Current proposal version
- Generated proposal
- Expiration information
- Creation and update information

Typical workflow states include:

Submitted
→ StudioMatching
→ PackageRecommendation
→ Scheduling
→ Validation
→ AwaitingApproval
→ Approved / Rejected

Other safe states can include:

- NeedsInput
- NoMatch
- Failed
- Cancelled
- Expired
- RevalidationRequired

## AiWorkflowEvents
`AiWorkflowEvents` stores an audit trail of important workflow transitions and events.

This makes it possible to understand how a recommendation progressed through the Agentic AI workflow.

The event history is useful for:

- Auditing
- Debugging
- Failure investigation
- Workflow history
- Demonstration and reporting

## AiWorkflowApprovals
`AiWorkflowApprovals` stores human approval or rejection information.

Approval information is kept separately so that the system can maintain an auditable record of human decisions related to AI-generated proposals.

## Proposal Versioning
AI proposals use version numbers.

The initial proposal starts with a version, and subsequent revisions increase the proposal version.

Approval and rejection operations reference the expected proposal version.

This helps prevent a user from approving an outdated recommendation.

## Revalidation
Persisted AI recommendations are not automatically considered valid forever.

Before approval, ASP.NET Core performs fresh deterministic validation.

Validation can include:

- Studio status
- Package status
- Service validity
- Current pricing
- Availability
- Booking conflicts
- Coverage requirements

If the stored recommendation is no longer valid, the workflow can move to `RevalidationRequired`.

## Failure Handling
AI or provider failures must not create partial bookings.

If the AI workflow cannot safely complete, the workflow records a safe failure state.

A failed recommendation does not automatically create or modify a booking.

## Database Ownership
ASP.NET Core is the only application layer responsible for authoritative PostgreSQL operations.

The Python Agentic AI service:

- Does not directly connect to PostgreSQL.
- Does not create bookings.
- Does not approve workflows.
- Does not modify authoritative pricing.
- Does not bypass backend authorization.

It returns structured AI workflow results to ASP.NET Core.

## Reasons
- Provides durable workflow state.
- Supports auditing of Agentic AI operations.
- Allows workflows to survive service restarts.
- Supports human approval.
- Prevents Python AI code from directly changing business data.
- Supports proposal versioning and stale-data detection.
- Makes failures traceable.
- Maintains ASP.NET Core as the authoritative backend.

## Alternatives Considered

### Store Workflow State Only in Python Memory
This was rejected because workflow information would be lost when the Python service restarts.

### Give Python Direct PostgreSQL Access
This was rejected because it would allow the AI service to bypass the authoritative ASP.NET Core business and authorization layers.

### Store Only the Final Recommendation
This was rejected because intermediate workflow events and approval history are important for auditing and failure investigation.

## Consequences

### Positive
- Durable AI workflow state.
- Clear audit trail.
- Better failure recovery.
- Human decisions can be recorded.
- Strong separation between AI reasoning and business data.
- Easier investigation of AI workflow failures.

### Negative
- Additional database tables are required.
- Workflow state transitions require careful validation.
- Proposal versioning and revalidation increase backend complexity.

## Decision Outcome
SnapSync AI persists Agentic AI workflow state, events, and human approvals in PostgreSQL through ASP.NET Core.

Python FastAPI and LangGraph are responsible for AI orchestration, while ASP.NET Core remains responsible for persistence, authorization, validation, and authoritative business operations.