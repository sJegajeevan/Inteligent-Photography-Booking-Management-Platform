# Booking messaging implementation

Customers can open **My Bookings → Booking Details → Message Studio** in Flutter. Studio owners can open **Messages** at `/studio/messages` in React, select a booking, read the conversation, and reply. Both clients support manual refresh and refresh after sending, loading/error/empty states, a 1000-character limit, and duplicate-submission prevention while sending. Studio conversations include bookings without messages so either participant can initiate.

## API and security

- `GET /api/bookings/{bookingId}/messages`: participant-only messages ordered by UTC sent time, then ID.
- `POST /api/bookings/{bookingId}/messages`: accepts only `{ "message": "..." }`; returns HTTP 201 with the saved message.
- `GET /api/bookings/conversations`: studio-only booking/customer/package context and latest-message previews.

All endpoints reuse `GetActor()` and `OwnedBookings(actor)`. Customers must own the booking; studio users must own its studio. Unavailable and nonexistent bookings return the same 404 response. JWT role and database role must agree. Sender identity/name/role come from the authenticated/database user; booking identity comes from the authorized route; timestamps come from the server UTC clock. Empty/whitespace and oversized messages are rejected. Reads use no-tracking EF queries and DTO projections that omit private user fields. Clients render messages as text.

No migrations, application database operations, schema changes, environment-file changes, authentication changes, commits, or pushes were performed. Backend tests create only disposable in-memory SQLite data. Existing changes to `ApplicationDbContext.cs`, `Models/BookingMessage.cs`, and `backend/database/booking-messages/` were preserved.

## Files created

- `backend/PhotographyBooking.Api/Controllers/BookingsController.Messages.cs`
- `backend/PhotographyBooking.Api/DTOs/BookingMessages/BookingMessageDtos.cs`
- `backend/tests/BookingMessageChecks/BookingMessageChecks.csproj`
- `backend/tests/BookingMessageChecks/Program.cs`
- `frontend/photography-web/src/pages/Studio/StudioMessages.jsx`
- `frontend/photography-web/src/pages/Studio/StudioMessages.css`
- `frontend/photography-web/tests/booking-messages.test.mjs`
- `mobile/photography_mobile/lib/models/booking_message.dart`
- `mobile/photography_mobile/lib/screens/booking/booking_conversation_screen.dart`
- `mobile/photography_mobile/test/booking_messages_test.dart`
- `BOOKING_MESSAGING_IMPLEMENTATION.md`

## Files modified

- `backend/PhotographyBooking.Api/Controllers/BookingsController.cs`: partial declaration to share the existing authorization helpers.
- `frontend/photography-web/src/services/bookingService.js`: messaging calls through the existing authenticated request helper.
- `frontend/photography-web/src/app.jsx`: protected Messages route.
- `frontend/photography-web/src/pages/Studio/StudioLayout.jsx`: active studio navigation entry and page title.
- `frontend/photography-web/src/pages/Studio/StudioDashboard.jsx`: Messages page integration.
- `mobile/photography_mobile/lib/services/booking_service.dart`: authenticated message requests and safe error handling.
- `mobile/photography_mobile/lib/screens/booking/booking_details_screen.dart`: Message Studio entry point.

## Verification

| Check | Result |
| --- | --- |
| `dotnet build backend/PhotographyBooking.Api/PhotographyBooking.Api.csproj --no-restore` | Passed, 0 warnings/errors |
| `dotnet run --project backend/tests/BookingMessageChecks/BookingMessageChecks.csproj` | 29 checks passed; real HTTP/JWT middleware, isolated SQLite |
| `dotnet run --project backend/tests/BookingCompletionChecks/BookingCompletionChecks.csproj --no-restore` | 40 existing checks passed |
| `npm run lint` | Final run passed with no findings |
| `npm test -- --test-name-pattern=messages` | Existing npm script ran all 31 tests; all passed, including 3 new messaging tests |
| `node --test tests/booking-messages.test.mjs` | 3 focused messaging tests passed |
| `npm run build` | Passed |
| `flutter analyze` | Final run passed: no issues found |
| `flutter test test/booking_messages_test.dart test/booking_workflow_test.dart` | All 10 tests passed |
| `git diff --check` | Passed |

Backend checks cover both participant roles, cross-customer/studio read and write denial, anonymous requests, forged identity/body fields, role mismatch, unknown bookings, text validation, timestamp ordering, studio list isolation, and server UTC timestamps. Flutter tests cover transport/authentication, validation, errors, duplicate taps, refresh after send, and preserved drafts following uncertain delivery. React automated tests cover service transport, validation, and error handling; browser interaction still needs manual verification.

## Manual integration testing remaining

1. Run the API against the existing PostgreSQL schema and sign in with a real customer and its booked studio owner.
2. Send from Flutter, refresh React Messages, reply, and refresh Flutter. Verify names, local display times, chronological order, and persistence after reopening.
3. Verify another customer and another studio receive 404 for that booking's message routes and cannot see it in their conversation lists.
4. Check the React page in desktop/narrow layouts and the Flutter screen on a device with the keyboard open, including long messages and connection loss.

No live PostgreSQL or real-device/browser end-to-end session was run. Conversations use REST refresh, with no polling, WebSockets, or third-party chat service.
