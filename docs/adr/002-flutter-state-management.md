# ADR 002: Flutter State Management

## Status
Accepted

## Context
SnapSync AI uses Flutter for the customer-facing mobile application.

The mobile application includes authentication, studio browsing, package selection, booking, AI recommendations, booking tracking, reviews, and customer profile features.

The application needs to manage screen-level state, API responses, loading states, form data, and navigation between customer workflows.

## Decision
Use Flutter's built-in state management mechanisms, primarily `StatefulWidget` and `setState`, for local UI state.

Application services are responsible for communicating with the ASP.NET Core REST API, while widgets manage the UI state required by individual screens.

## Reasons
- Suitable for the current project size.
- Keeps the mobile architecture simple.
- Avoids unnecessary state-management dependencies.
- Easy for all team members to understand.
- Provides sufficient control for forms, loading states, API results, and user interactions.

## Alternatives Considered

### Provider
Provider can manage shared application state effectively, but the current application does not require enough complex shared state to justify introducing it across the project.

### Riverpod
Riverpod provides scalable and testable state management, but it would introduce additional architectural complexity for the current scope.

### BLoC
BLoC provides strong separation between business logic and presentation but requires considerably more boilerplate and architectural setup.

## Consequences

### Positive
- Simple implementation.
- Fewer external dependencies.
- Easier debugging and maintenance.
- Appropriate for the current customer workflows.

### Negative
- Complex screens can require more manual state handling.
- If the application grows, a dedicated state-management solution may become beneficial.

## Decision Outcome
Flutter's built-in state management is sufficient for the current SnapSync AI mobile application.