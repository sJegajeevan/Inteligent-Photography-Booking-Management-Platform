# Studio location and Near Me

## API

The existing JWT-protected `GET/PUT /api/studio/profile` now reads/writes
nullable `latitude` and `longitude`. PUT still uses multipart form data.
Supply both coordinates, or send both empty/omit both to clear them.
Latitude is -90 through 90; longitude is -180 through 180. The API rejects
incomplete pairs, malformed numbers and out-of-range values. Coordinates use
the existing database precision of six decimal places. Address and Location
keep their existing meaning. The signed-in Studio user's claim selects the
profile; clients cannot supply another owner's ID.

`GET /api/public/studios/nearby?latitude=6.9271&longitude=79.8612&radiusKm=50`
returns the existing public summary fields plus `distanceKm`. Customer
coordinates are required, finite and range-validated. Optional radius must be
greater than zero and at most 500 km. Omitting radius returns all studios with
valid coordinates, nearest first. Ties use studio name then ID. Filtering uses
unrounded distances. Existing `search`, `location`, and `service` query filters
work on both listing endpoints. Studios without coordinates stay in ordinary
browsing and are excluded from nearby results. Empty results return `[]`.

DistanceService uses Haversine with mean Earth radius 6371.0088 km, including
clamping for numerical stability at antipodes. These are straight-line
distances, not driving routes. The service is registered as a singleton and is
pure: a future Studio Matching Agent can inject it and call
`CalculateKilometers(customerLat, customerLon, studioLat, studioLon)` as a
deterministic tool. No AI has been implemented.

## Interfaces and privacy

React's existing profile editor has optional Latitude/Longitude inputs and
pair/range validation. Existing coordinates are shown on the profile. Clear
both inputs and save to remove coordinates. No Google Maps key is needed.

Flutter uses `geolocator: ^14.0.3` through LocationService. The existing browse
screen requests a single foreground location only after tapping Near Me.
Results within 50 km reuse StudioCard and existing navigation, show distance,
and retain search. All studios exits nearby mode. GPS disabled, denied,
permanently denied, timeout and retrieval errors have readable messages;
nearby HTTP failures return to normal browsing. Empty nearby results offer
All studios. GPS fixes time out after 15 seconds; HTTP requests after 20.
Late results are ignored when the screen is disposed or All studios selected.

Customer coordinates are transient request values: no database writes, local
storage, analytics or application logging is added. Nearby responses disable
caching. Use HTTPS in deployment and configure reverse-proxy/access logging
to omit query strings on the nearby route. Existing ASP.NET logging sets
Microsoft.AspNetCore to Warning. Do not enable request URL tracing for GPS
requests. Public nearby responses add distance only, not owner IDs or precise
studio coordinates. Existing JWT authorization is unchanged.

## Google Maps foundation

- React: `VITE_GOOGLE_MAPS_API_KEY`, documented empty in `.env.example`, read by
  `src/config/googleMaps.js`. This is a configuration boundary only: no map,
  marker picker, geocoding or Google script is currently loaded. A browser key
  would be public in the bundle and must be restricted to approved origins/APIs.
- Backend, only for a future Google integration: `GoogleMaps__ApiKey` environment
  variable (ASP.NET configuration key `GoogleMaps:ApiKey`). Keep it in the
  deployment secret store. No backend Google calls or key are required today.
- Haversine and device GPS require no Google Maps key. No real key was added.

## Verification and remaining setup

- `dotnet build` reached compilation but failed copying the apphost because the
  existing API process holds the executable open. `dotnet build -o
  bin/location-verification` succeeded with zero warnings/errors.
- `dotnet run --project backend/tests/LocationChecks`: 18 checks passed (known
  distances, zero, symmetry, antimeridian, antipodes, nonfinite/range rejection,
  nullable coordinate pairs). No database connection.
- `npm run build`: passed.
- React lint: six errors in unrelated pre-existing files; changed location
  files produced no reported lint errors.
- `flutter pub get` and `flutter analyze`: attempted but stalled in this
  restricted environment and stopped. Permission for external cache updates /
  dependency downloads was declined. Dependency lockfile generation and mobile
  verification remain incomplete. Dart formatting succeeded.
- Added `test/nearby_studios_test.dart` for opt-in GPS, API query parameters,
  distance display, All studios and failure fallback; not executed here.

On the development machine, run `flutter pub get`, `flutter analyze`, and
`flutter test`. Rebuild/restart the backend to load the new endpoint. Configure
Flutter `API_BASE_URL` for the device's reachable backend. Android foreground
location permissions and iOS When In Use description are included. On macOS,
the location entitlement and usage description are included. Device GPS and
permission prompts need physical-device/emulator testing. Browser geolocation
requires a secure context (HTTPS or localhost). See the package's
[platform setup instructions](https://pub.dev/packages/geolocator), especially
iOS foreground-only build configuration (`BYPASS_PERMISSION_LOCATION_ALWAYS=1`
where required by the selected plugin build integration). No background
location feature is used.

Manual acceptance: save/reload a coordinate pair and then clear it; verify an
invalid/half pair is rejected; confirm another Studio account cannot change
the first profile; test denied/permanently denied/disabled/timeout GPS, nearby
empty/offline results and return to normal browsing; confirm studios without
coordinates remain browseable and bookable. Live database and device checks
were not performed in this task.

## Files changed for this feature

- Backend: `DTOs/Studio/UpdateStudioDto.cs`, `StudioResponseDto.cs`,
  `DTOs/PublicStudios/PublicStudioDtos.cs`, `Services/StudioService.cs`,
  `Services/DistanceService.cs`, `Controllers/PublicStudiosController.cs`,
  `Program.cs`, `backend/tests/LocationChecks/{LocationChecks.csproj,Program.cs}`.
- React: `src/pages/Studio/StudioProfile.jsx`,
  `src/services/studioProfileService.js`, `src/config/googleMaps.js`, `.env.example`.
- Flutter: `pubspec.yaml`, `lib/services/location_service.dart`,
  `lib/services/studio_service.dart`, `lib/models/studio.dart`,
  `lib/widgets/studio_card.dart`, `lib/screens/studio/studio_list_screen.dart`,
  `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`,
  `macos/Runner/Info.plist`, `macos/Runner/DebugProfile.entitlements`,
  `macos/Runner/Release.entitlements`, `test/nearby_studios_test.dart`.
- This document: `docs/studio-location.md`.

DATABASE SCHEMA CHANGED: NO

MIGRATIONS RUN: NO

CUSTOMER GPS STORED IN DATABASE: NO

REAL GOOGLE API KEY COMMITTED: NO

No commits or pushes were made. Existing unrelated workspace changes were kept.
