# Studio coordinates deployment — 2026-09-21

Completed the explicitly authorized schema/model change against the configured
`photography_booking_db`. Stopped before Maps/GPS, Flutter or React changes.

1. **Backup:** `photography_booking_before_studio_coordinates_20260921T081022Z.backup`,
   PostgreSQL custom format, 41,470 bytes. `pg_dump` exit 0; `pg_restore --list` exit 0,
   94 archive entries. SHA-256:
   `2C2E783DE8804952FCF710018AF641770A99478713BDC8EB7834B644734ECA36`.
   Stored in this directory; never overwrote an existing backup. The local `.gitignore`
   excludes backup files containing business/account data. No restore was performed.
2. **Preflight:** Offline migration/SQL match and patch applicability passed. Live
   read-only verification confirmed the reviewed 14-column ordinary Studio table,
   absent coordinate columns/constraint and no enabled DDL event triggers. Captured
   original column/constraint metadata and all public-table content fingerprints.
3. **SQL applied:** Exactly `20260921000100_add_studio_coordinates.sql`, using
   `psql -X --set=ON_ERROR_STOP=1 --file ...` and its existing BEGIN/COMMIT transaction.
   Exit 0. See `application-verification.json` for the applied file hash and UTC time.
   No other SQL deployment, migration chain, reset or database recreation was run.
4. **Latitude:** `public.Studios.Latitude numeric(9,6) NULL`, no default.
5. **Longitude:** `public.Studios.Longitude numeric(9,6) NULL`, no default.
6. **Constraint:** `CK_Studios_Coordinates`, validated CHECK. Both coordinates must
   be null, or both present with latitude [-90,90] and longitude [-180,180]. Read-only
   evaluation of the actual stored constraint passed 13 cases: null pair, zero,
   boundary coordinates, normal coordinates, partial pairs, out-of-range values and
   PostgreSQL numeric NaN. No sample Studio rows were inserted or updated.
7. **Studio preservation:** The existing one Studio row, including its ID, owner
   and all previous field values, has the same fingerprint. Both new values are null.
8. **Other business data:** All 15 public table counts/fingerprints match exactly:

   | Table | Rows before and after |
   | --- | ---: |
   | Users | 6 |
   | Studios | 1 |
   | PhotographyPackages | 1 |
   | PhotographyPackageServices | 1 |
   | StudioPortfolios | 2 |
   | StudioPortfolioImages | 4 |
   | StudioServices | 1 |
   | StudioAvailabilities | 1 |
   | Bookings | 0 |
   | BookingLocations | 0 |
   | BookingStatusHistories | 0 |
   | Notifications | 0 |
   | PackageAddons | 0 |
   | Reviews | 0 |
   | __EFMigrationsHistory | 1 |

   Verification compared every pre-existing column/constraint definition too; only
   the authorized two columns and one CHECK were added. Evidence is in
   `verification-before.json` and `verification-after.json`; no raw business rows
   were exported to these JSON files.
9. **Runtime model files:** `Models/Studio.cs` now contains nullable decimals, range
   annotations and paired-coordinate `IValidatableObject` validation.
   `Data/ApplicationDbContext.cs` maps precision (9,6) and the exact CHECK expression.
   EF does not automatically execute DataAnnotations on SaveChanges; PostgreSQL
   enforces the invariant for all writes. Existing DTOs and APIs are unchanged.
10. **Build/model verification:** API `dotnet build` passed with zero warnings/errors.
    Offline `StudioLocationPreparation --verify-model` confirmed coordinate types,
    nullability, precision, matching CHECK and 11 model-validation cases. The tool
    confirms archived migrations remain excluded and prohibits database connections.
11. **EF migration history changed: NO.** This was a controlled SQL deployment,
    not an EF migration-chain execution. Retain its artifact hash/backup/evidence;
    do not insert a fabricated EF history row. Reconcile a future EF baseline
    separately against the actual database if EF-managed deployments are adopted.
12. **Issue encountered:** The first postflight comparison falsely reported changed
    content because Windows PowerShell 5.1 serialized the original result array with
    a `value`/`Count` wrapper. The verifier was corrected to compare the underlying
    records without modifying the original evidence. Subsequent read-only checks
    passed; no database repair, data update or SQL retry was needed. No SQL failed.

Additional deployment-support files: `Verify-StudioCoordinates.ps1`, `.gitignore`,
`backup-verification.json`, `application-verification.json`, before/after evidence,
this report and updated README. The existing offline tool gained `--verify-model`.

DATABASE CHANGED: YES  
COORDINATE SQL APPLIED: YES  
ARCHIVED MIGRATIONS RUN: NO  
DATA DELETED: NO  
BACKUP CREATED: YES

No Google Maps/GPS implementation, Flutter/React edits, commit or push.
