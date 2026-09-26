# ADR 003: Agentic AI Orchestration

## Status
Accepted

## Context
SnapSync AI includes an Agentic AI workflow for assisting customers with photography booking decisions.

The workflow contains four distinct agents:

1. Studio Matching Agent
2. Package Recommendation Agent
3. Scheduling Agent
4. Validation and Safety Agent

The agents must operate as one coordinated workflow rather than as independent chatbots.

The main ASP.NET Core backend remains responsible for authentication, database access, authoritative business rules, pricing, availability validation, and approval operations.

## Decision
Use Python FastAPI and LangGraph to implement and orchestrate the Agentic AI workflow.

Gemini is used as the Large Language Model (LLM) for reasoning and recommendation tasks.

The architecture is:

Flutter / React → ASP.NET Core API → FastAPI → LangGraph → Gemini

Client applications do not communicate directly with FastAPI or Gemini.

ASP.NET Core communicates with the internal Python service through a protected internal endpoint.

## Agent Workflow
The workflow follows these main stages:

Submitted
→ Studio Matching
→ Package Recommendation
→ Scheduling
→ Validation
→ Awaiting Human Approval

Each agent performs a distinct responsibility and passes structured information to the next stage.

## Responsibilities

### Studio Matching Agent
Identifies suitable studios based on customer requirements such as photography type, location, and preferences.

### Package Recommendation Agent
Recommends suitable photography packages based on customer requirements, requested services, coverage duration, and budget.

### Scheduling Agent
Suggests appropriate scheduling options based on the requested date range and availability information.

### Validation and Safety Agent
Checks the generated recommendation before it is presented for human approval.

## Deterministic Validation
AI output is not treated as authoritative business data.

ASP.NET Core performs deterministic validation for important information including:

- Studio existence and status
- Package and service validity
- Pricing
- Availability
- Booking conflicts
- Coverage duration
- Authorization

This prevents the AI from directly changing authoritative business data.

## Human Approval
The AI produces a recommendation rather than directly creating a booking.

The generated proposal is persisted and presented for human review. An authorized studio owner or administrator can approve or reject the proposal.

Final booking operations still pass through the normal backend validation process.

## Reasons
- LangGraph supports multi-step agent workflows.
- Each agent can have a clear and auditable responsibility.
- FastAPI provides a lightweight interface between ASP.NET Core and Python.
- Gemini provides LLM-based reasoning while deterministic rules remain in ASP.NET Core.
- Human approval reduces the risk of unsafe or incorrect AI actions.
- The architecture keeps API keys and internal AI services away from client applications.

## Alternatives Considered

### Single LLM Request
A single Gemini request would be simpler but would not provide clear separation between the four required agent responsibilities.

### Direct Client-to-Gemini Communication
This was rejected because it would expose AI credentials and bypass backend validation and authorization.

### AI Direct Database Access
This was rejected because the AI workflow should not directly modify authoritative application data.

## Consequences

### Positive
- Clear separation of agent responsibilities.
- Auditable multi-step workflow.
- AI failures can fail safely without creating a booking.
- Sensitive AI credentials remain server-side.
- Business rules remain deterministic and controlled by ASP.NET Core.

### Negative
- Introduces an additional Python service.
- Requires communication between ASP.NET Core and FastAPI.
- External Gemini availability can affect recommendation generation.
- Deployment is more complex than a single backend service.

## Decision Outcome
SnapSync AI uses FastAPI, LangGraph, and Gemini for Agentic AI orchestration while ASP.NET Core remains the authoritative application backend.