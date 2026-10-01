# WhatsApp booking contact

Booking Details now has a themed Contact Studio section with a prominent **Chat on WhatsApp** button and **Message in SnapSync** linking to the existing conversation screen.

The backend needed one additional response field: `StudioContactNumber`, mapped from the booked studio's existing `ContactNumber`. Existing booking authorization is unchanged. No database/schema changes were made.

The Flutter helper normalizes Sri Lankan `0…`, `+94…`, and `94…` numbers, removes ordinary formatting, and rejects missing/malformed numbers. It builds `https://wa.me/{internationalNumber}?text={encodedMessage}` using `Uri.https`. The draft contains studio name, booking number, date, and start/end times only. `url_launcher` opens it externally so the operating system can use WhatsApp or a browser. Invalid contact and launch failures produce friendly feedback; internal messaging stays available.

## Files changed for this addition

- Modified `backend/PhotographyBooking.Api/DTOs/Bookings/BookingResponse.cs`
- Modified `backend/PhotographyBooking.Api/Controllers/BookingsController.cs`
- Extended `backend/tests/BookingMessageChecks/Program.cs`
- Modified `mobile/photography_mobile/lib/services/booking_service.dart`
- Modified `mobile/photography_mobile/lib/screens/booking/booking_details_screen.dart`
- Modified `mobile/photography_mobile/pubspec.yaml`
- Modified `mobile/photography_mobile/pubspec.lock`
- Added `mobile/photography_mobile/lib/services/booking_whatsapp.dart`
- Added `mobile/photography_mobile/test/booking_whatsapp_test.dart`
- Added this report.

Only [url_launcher 6.3.2](https://pub.dev/packages/url_launcher) and its required platform packages were added; existing dependency versions were preserved.

## Verification

- Normal backend build could not overwrite the executable held by the running API. The API and focused test project then built successfully into `.studio-verification/whatsapp/` outside the repository: **0 warnings, 0 errors**. The running API was not stopped.
- Focused backend HTTP/JWT checks against ephemeral SQLite: **32 passed**, including the new contact field and cross-customer/studio contact access denial.
- `flutter analyze --no-pub`: **no issues found**.
- `flutter test --no-pub test/booking_whatsapp_test.dart test/booking_messages_test.dart test/booking_workflow_test.dart`: **20 passed** after making the launch-failure mock deterministic.
- `flutter pub get` resolved/downloaded the dependency and updated the lockfile, then exited with a Windows plugin-symlink error requiring Developer Mode. Analysis/tests used the resolved dependencies with `--no-pub`; a native app build was not run.

## Manual testing

Enable Windows Developer Mode for Flutter plugin symlink support, then rerun `flutter pub get`. Restart the API and rebuild the Flutter app to pick up the new response field and native plugin. Verify the booked studio's actual number opens the intended WhatsApp chat, the draft contents, browser fallback without WhatsApp installed, and both contact options on a physical device. A syntactically valid number does not establish that it has a WhatsApp account.

Existing internal messaging, Google Maps work, `.env` files, and PostgreSQL data/schema were left intact. No commit or push was performed.
