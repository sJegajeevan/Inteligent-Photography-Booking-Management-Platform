# ADR 001: React State Management

## Status
Accepted

## Context
SnapSync AI uses React with Vite for the web application. The web application includes authentication, studio management, portfolio management, services, availability, bookings, administration, and AI workflow review interfaces.

The application requires shared authentication information and page-level data retrieved from the ASP.NET Core REST API.

## Decision
Use React's built-in state management features such as `useState`, `useEffect`, and Context where shared state is required.

API-related data is retrieved from the ASP.NET Core backend and maintained close to the components that use it.

Authentication information is shared through the application's authentication mechanism instead of introducing an additional global state management library.

## Reasons
- Keeps the application architecture simple.
- Avoids unnecessary dependencies.
- Suitable for the current project size.
- Easy for all team members to understand and maintain.
- Works well with the existing REST API architecture.

## Alternatives Considered
### Redux
Redux provides centralized state management but introduces additional configuration and complexity that is not required for the current application.

### Zustand
Zustand provides lightweight global state management, but the current application does not require enough complex global state to justify adding another dependency.

## Consequences
### Positive
- Less boilerplate code.
- Easier maintenance.
- Lower learning overhead for the team.
- State remains close to the UI that consumes it.

### Negative
- If the application grows significantly, managing shared state across many components may become more difficult.
- Additional state management solutions may be required in the future.

## Decision Outcome
React built-in state management is sufficient for the current SnapSync AI web application.