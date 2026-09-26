# ADR 005: Deployment Architecture

## Status
Accepted

## Context
SnapSync AI is an integrated photography booking and management platform consisting of multiple application components:

- React web application
- Flutter mobile application
- ASP.NET Core Web API
- PostgreSQL database
- Python FastAPI Agentic AI service
- LangGraph workflow orchestration
- Gemini API integration

The system requires a deployment architecture that keeps business logic, database access, authentication, and AI credentials secure while allowing both React and Flutter clients to use the same backend.

## Decision
Use ASP.NET Core as the public application backend and keep the Python FastAPI Agentic AI service as an internal service.

The deployment architecture is:

React Web Application
        ↓
ASP.NET Core Web API
        ↓
PostgreSQL Database
        ↓
Internal FastAPI Service
        ↓
LangGraph
        ↓
Gemini API

The Flutter mobile application also communicates with the same ASP.NET Core Web API.

Therefore, both client applications share the same authentication, business rules, database, and API layer.

## Public Application Layer
The React application provides the web interface for studio owners and administrators.

The Flutter application provides the mobile interface primarily for customers.

Neither client directly connects to PostgreSQL, FastAPI, LangGraph, or Gemini.

## ASP.NET Core API
ASP.NET Core acts as the main public backend.

It is responsible for:

- Authentication and authorization
- JWT validation
- Business rules
- CRUD operations
- Booking management
- Pricing validation
- Availability validation
- Database access
- AI workflow persistence
- Human approval operations
- Communication with the internal Python service

## PostgreSQL
PostgreSQL stores the authoritative application data.

This includes:

- Users
- Studios
- Portfolios
- Services and packages
- Availability
- Bookings
- Reviews
- AI workflows
- AI workflow events
- AI approvals

Database access is controlled through the ASP.NET Core backend.

## Internal Agentic AI Service
FastAPI hosts the Python Agentic AI workflow.

It is not intended to be directly exposed to React or Flutter clients.

ASP.NET Core communicates with the internal FastAPI service using a protected internal endpoint and internal authentication token.

LangGraph coordinates the four AI agents:

1. Studio Matching Agent
2. Package Recommendation Agent
3. Scheduling Agent
4. Validation and Safety Agent

Gemini is accessed only from the server-side AI service.

## Security
Sensitive credentials must not be committed to Git.

Examples include:

- Database credentials
- JWT signing keys
- Gemini API keys
- Internal workflow tokens

Environment variables or local/deployment-specific configuration are used for secrets.

The client applications must never receive the Gemini API key or internal service token.

## Deployment Configuration
Deployment-specific settings are supplied using environment variables.

Examples include:

- Database connection string
- JWT configuration
- Python AI service base URL
- Internal workflow token
- Gemini API key
- Google Maps API configuration where required

## Continuous Integration
GitHub Actions is used for Continuous Integration.

The CI pipeline validates the major project components by running:

- ASP.NET Core restore and build
- React dependency installation and production build
- Flutter dependency installation, analysis, and tests
- Python Agentic AI dependency installation and tests

This helps detect integration problems before deployment.

## Health and Verification
The deployed ASP.NET Core API should provide appropriate health or API verification endpoints and Swagger/OpenAPI access where suitable.

The deployment process should verify:

- ASP.NET Core API availability
- PostgreSQL connectivity
- React application availability
- Internal FastAPI connectivity
- Required environment configuration

## Flutter Distribution
The Flutter application is distributed separately as a mobile application.

A release APK should be generated for project demonstration and assessment.

The APK communicates with the deployed ASP.NET Core API rather than directly accessing the database or AI provider.

## Reasons
- Maintains one authoritative backend.
- React and Flutter share the same business rules.
- Protects database and AI credentials.
- Prevents clients from bypassing backend validation.
- Keeps the Python AI service isolated from public clients.
- Supports independent deployment of web, backend, database, and AI services.
- Supports automated CI verification.

## Alternatives Considered

### Direct Client-to-Database Access
Rejected because it would bypass backend authentication, authorization, and business rules.

### Direct Client-to-Gemini Access
Rejected because it could expose the Gemini API key and bypass deterministic backend validation.

### Separate Backends for React and Flutter
Rejected because separate backends could duplicate business logic and create inconsistent behaviour between platforms.

### Combine Python AI Code into ASP.NET Core
Rejected because the Agentic AI workflow uses Python libraries such as LangGraph and the Gemini Python SDK.

## Consequences

### Positive
- Clear separation of responsibilities.
- Improved security.
- Shared business rules across web and mobile.
- AI service can fail without directly affecting authoritative database operations.
- Components can be deployed and scaled independently.
- CI can validate each technology separately.

### Negative
- Multiple services must be configured and deployed.
- Internal ASP.NET Core to FastAPI communication must be maintained.
- Environment variables and secrets must be configured correctly.
- External AI provider availability can affect AI recommendation workflows.

## Decision Outcome
SnapSync AI uses ASP.NET Core as the public authoritative backend, PostgreSQL as the authoritative database, and FastAPI with LangGraph as an internal Agentic AI service.

React and Flutter communicate only with ASP.NET Core, while external AI services remain protected behind the backend architecture.