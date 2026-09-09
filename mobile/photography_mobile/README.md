# Customer Studios

The app opens the public Studios list. All studio content comes from the existing ASP.NET Core API; no sample studios are bundled.

## Run in Chrome

From the repository root, start the backend (requires the existing PostgreSQL database/configuration):

```powershell
dotnet run --project backend/PhotographyBooking.Api --launch-profile http
```

In another terminal:

```powershell
cd mobile/photography_mobile
flutter pub get
flutter run -d chrome --web-port 5174
```

The development-only backend CORS policy allows GET requests from `http://localhost:5174`. Production CORS behavior is unchanged.

`lib/services/api_config.dart` centralizes the backend URL, defaulting to `http://localhost:5284` from the backend HTTP launch profile. Override it with `--dart-define=API_BASE_URL=https://your-api.example` when needed. A physical device needs a reachable backend host; localhost refers to that device. Backend-provided absolute image URLs also need to be accessible to that device.

## API contract

- `GET /api/public/studios` returns an array.
- `GET /api/public/studios/{studioId}` returns the selected studio.
- Both existing routes allow anonymous access.
- Model fields: `id`, `studioName`, `location`, `descriptionSummary` (list), `description` (detail), `profileImageUrl`, `coverImageUrl`, `photographyTypes`, `startingPrice`.
- Additional detail contact fields are intentionally not consumed yet.
- Existing portfolio, services and availability endpoints can be added as separate detail sections later; no extra requests are made now.

Search filters loaded studio names, locations and photography types without extra API calls. Relative image URLs resolve against the centralized backend URL. Missing, invalid or failed images show placeholders. HTTP failures and invalid responses produce a controlled error with Retry.

## Checks

```powershell
flutter analyze
flutter test
flutter test tool/live_studios_test.dart
flutter build web
```

The opt-in live test requires the backend running and at least one owner-created Studio. It tests the actual API, search and detail navigation at 390 x 844 without creating database records. Widget tests exercise empty/error responses and retry without embedding dummy Studios.

For visual verification in Chrome, set DevTools device dimensions to 390 x 844. Check the real studio's cover/profile images, search by name/location/type, open View Studio, then stop the backend and use Retry to check connection recovery.
