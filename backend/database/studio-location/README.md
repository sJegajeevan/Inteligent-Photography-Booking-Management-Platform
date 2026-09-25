# Studio location foundation — applied coordinate schema

Status: **APPLIED to the configured `photography_booking_db` on 2026-09-21**, after
explicit user authorization, live read-only preflight and a fresh custom-format
backup. Only the prepared transactional SQL was executed. The current Studio model
now maps nullable latitude/longitude. See `deployment-report.md` and the verification
JSON files for evidence. Do not reapply the SQL or model patch to this database.
Maps, GPS, nearby search, distance calculation and agent integration remain pending.

## Original inspection evidence (before deployment)

On 2026-09-21, a read-only transaction against the database configured by the
existing API's `ConnectionStrings:DefaultConnection` inspected
`information_schema.columns` for `public.Studios`, then rolled back. It found
14 columns, including `Location` and `Address`, but no `Latitude` or `Longitude`.
No customer/studio records or secret values were printed, and no data or schema
was changed. This verifies the configured local database only, not other deployments.

The existing Studio model, owner DTO/service/controller and public DTO/controller
support a human-readable location/address. React already edits both fields through
the existing JWT-protected multipart Studio Profile endpoint. Flutter browses studios
and filters by text/location; its Studio model currently omits the detail API's address.

`BookingLocation.Latitude` and `BookingLocation.Longitude` are nullable decimal
event-venue coordinates mapped as `numeric(9,6)`. They belong to bookings and must
not be repurposed as studio coordinates or customer live GPS storage. The repository
has no Google Maps/geolocation implementation, `geolocator` or `google_maps_flutter`
dependency, location permission declarations, or Google Maps configuration section.
Flutter uses `API_BASE_URL`; React uses `VITE_API_URL`.

The API excludes `Migrations/**/*.cs` from compilation because its archived migration
chain does not describe the database. Existing reconciliation artifacts explicitly
use separately reviewed deployment SQL. Do not re-enable that chain or run
`dotnet ef database update` to deploy this change.

## Exact applied database change

Added only the following to the existing `public.Studios` table:

| Object | Definition |
| --- | --- |
| `Latitude` | nullable `numeric(9,6)`; no default |
| `Longitude` | nullable `numeric(9,6)`; no default |
| `CK_Studios_Coordinates` | Both coordinates null, or both present with latitude in [-90, 90] and longitude in [-180, 180] |

Keep existing `Location` and `Address`. Existing studios retain unknown coordinates
as null; `(0,0)` is a real coordinate and is not a missing-location marker. There
is no backfill, geocoding, new location table, customer GPS storage, spatial
extension, or change to migration history. No existing column is changed or removed.

## Review artifacts and checks

- `20260921000100_AddStudioCoordinates.cs`: review-only EF Core migration with
  `Up` and `Down`; compiled only by the offline preparation tool. It is not an
  active migration chain or a replacement baseline/snapshot.
- `20260921000100_add_studio_coordinates.sql`: the exact Npgsql-generated deployment
  SQL wrapped in a transaction, with bounded lock/statement timeouts and preflight
  checks. It stops if the table is absent or either coordinate/constraint already
  exists, rather than guessing how to reconcile a different schema. Applied without
  edits; its original preparation header is retained to preserve the reviewed hash.
- `model-after-schema.patch`: matching Studio properties and EF mapping/constraint
  changes. **Applied after the schema commit.** Studio also now has decimal range
  annotations and `IValidatableObject` paired-coordinate validation. EF SaveChanges
  does not automatically run DataAnnotations; the mapped database CHECK remains the
  authoritative enforcement for every database write.
- `../../tools/StudioLocationPreparation/`: offline compiler/generator/verifier.
  No apply mode, configuration loading, API startup or database access; an EF
  connection interceptor rejects connection attempts.

From `backend`, these commands only generate/verify local files:

```powershell
dotnet run --project tools/StudioLocationPreparation/StudioLocationPreparation.csproj -- --generate database/studio-location/20260921000100_add_studio_coordinates.sql
dotnet run --project tools/StudioLocationPreparation/StudioLocationPreparation.csproj -- --verify database/studio-location/20260921000100_add_studio_coordinates.sql
```

On an unpatched source baseline only, the patch can be checked without applying it:

```powershell
git apply --check backend/database/studio-location/model-after-schema.patch
```

## Deployment procedure (completed for this local database)

1. Review these artifacts against the intended target database. Confirm its table,
   existing columns and deployment state; do not assume the local inspection applies
   to production. Arrange the normal backup and a brief maintenance window: adding
   columns/check constraints requires a table lock.
2. Only after explicit deployment authorization, execute the complete prepared SQL
   file through the project's controlled SQL deployment process with stop-on-error
   behavior. Do not execute the archived migrations or the earlier reconciliation.
3. Verify the two columns and constraint. Then review/apply `model-after-schema.patch`
   and build the API. Do not deploy the mapped model before the schema exists.
4. Stop at the schema/model boundary for this task. Future location work belongs in
   the existing Studio Profile/public discovery/Flutter browsing flow. No location
   UI or new DTO contract was introduced by this deployment.

The migration's `Down` drops the new columns and would discard coordinates entered
after deployment. It is review-only and must never be executed automatically.

## Remaining feature work after schema approval

- Extend owner DTOs and the existing profile update service with paired-coordinate
  validation. Preserve coordinates when an older client omits location updates;
  provide an explicit clear-location action instead of silently clearing them.
  Continue deriving ownership solely from the JWT user ID.
- Add a location picker/preview inside the existing React Studio Profile form.
  Handle missing keys, service errors and timeouts without blocking ordinary profile
  editing. Let owners confirm the studio pin; do not infer studio location from a
  customer's GPS or automatically replace addresses.
- Add a reusable backend distance service with validated coordinate inputs,
  deterministic great-circle distances in kilometers and nearest-first ordering.
  This is straight-line distance, not Google road distance or travel duration.
  Studios without coordinates must not receive fabricated distances. Keep ordinary
  browsing/search/filter results available, including studios without coordinates.
- Add optional customer-triggered Near Me with foreground-only GPS. Handle denied,
  permanently denied, services disabled, unsupported platform, timeout and retrieval
  failure; retain normal browsing. Keep customer coordinates transient and avoid
  including them in URLs/access logs or sending them to Google unnecessarily.
- Add appropriate studio coordinate/distance fields to public discovery responses,
  tests for coordinate limits/null pairs/distance calculations, GPS error handling,
  API failures and existing profile authorization.
- A future Studio Matching Agent can call the same deterministic distance service.
  No LLM, agent or AI ranking is part of this work.

No new configuration is required for these review artifacts. Google Cloud setup is
**deferred** because no Maps integration was activated. When that work resumes,
choose the necessary Google API(s), enable them and configure appropriately
restricted keys outside Git. A future server-side integration can use
`GoogleMaps:ApiKey` / `GoogleMaps__ApiKey`; that key is a proposed name, not currently
consumed by the application. Browser keys require separate browser restrictions
and must never be described as secret once delivered to a browser. No API key was
created, stored, printed or committed in this task.

## Historical verification during preparation

- API `dotnet build`: passed, zero warnings/errors.
- Offline migration generation: passed, without a database connection.
- Offline migration/SQL verification and model patch check: passed.
- React `npm run build`: passed.
- React `npm run lint`: six existing errors in unchanged files (`Modal.jsx`,
  `AuthContext.jsx`, `AdminDashboard.jsx`, `studioCustomersService.js`,
  `studioReviewsService.js`, `vite.config.js`). Left unchanged.
- Flutter `flutter analyze`: execution approval declined; not run for this task.
  No Flutter files/dependencies were changed.

## Current deployment verification

- Fresh custom-format backup succeeded; archive table-of-contents read succeeded.
- Exact SQL committed successfully; both columns are nullable `numeric(9,6)` with
  no defaults. The validated CHECK passes 13 read-only pair/range boundary cases.
- All 15 public table row counts and pre-existing row fingerprints are unchanged.
  Original column/constraint metadata is unchanged. Existing coordinates are null.
- EF migration history is unchanged (one existing entry). No fake history was added.
- `dotnet build`: passed, zero warnings/errors.
- Offline `--verify-model`: passed, including exact EF mapping/constraint agreement
  and 11 DataAnnotations/pair-validation cases, without opening a connection.
- `Verify-StudioCoordinates.ps1` uses read-only transactions for preflight/postflight;
  it preserves existing evidence rather than overwriting it. Original before evidence
  retains its Windows PowerShell array wrapper; the verifier normalizes that wrapper
  when comparing actual table fingerprints.

DATABASE CHANGED: YES  
COORDINATE SQL APPLIED: YES  
ARCHIVED MIGRATIONS RUN: NO  
EF MIGRATION HISTORY CHANGED: NO  
DATA DELETED: NO  
BACKUP CREATED: YES  
API KEY COMMITTED: NO

No commit or push. Only the Studio coordinate model/mapping/validation was added to
runtime code. Existing API contracts, authorization, profile CRUD, booking behavior,
Flutter UI and React UI were not changed. Track this as a reviewed SQL deployment;
do not record it as execution of the archived EF chain. Any future EF baseline must
be reconciled with the actual schema through a separately reviewed process.
