# Controlled reconciliation: preparation only

## Disposable test-studio cleanup (rollback-only dry run)

`cleanup_orphan_test_studio.sql` is a separate, guarded rehearsal exclusively for
operator-confirmed disposable test data owned by missing StudioId
`635a1ffa-c57e-436f-a6f8-a40821582173`. The operator reports a verified backup at
`photography_booking_before_cleanup.backup`. Preparation performs static review only.
The script does not run reconciliation or migrations and ends with `ROLLBACK`.

It requires the Studio to remain absent and the confirmed parent counts to remain
1 package, 3 services, 3 availabilities and 4 portfolios. Missing optional join/image
tables are skipped; missing confirmed parent tables abort. It counts dependencies,
rejects cross-studio package/service links, unexpected ownership IDs, external FK
references, and outside-scope UUID/text-ID references (including optional bookings
and package add-ons). It rejects table features that could hide or expand the work,
including RLS and enabled custom triggers on deletion targets. Embedded references
in JSON/free text cannot be established by these relational checks.

Use a quiet maintenance window: this dry run locks existing application tables
against concurrent writes, with a 5-second lock timeout. No other schema changes
should run concurrently. Run the entire file using `psql -X --set=ON_ERROR_STOP=1`;
permission errors, changed counts, or unexpected dependencies require review, not
weaker guards. On error the transaction aborts; psql disconnect rolls it back.
Deletion counts and verification notices use the original captured IDs. Final
SELECTs show the hypothetical state before rollback. The current Studio
`fa245b2d-5fa0-4255-91ee-783b21a9911f` is protected and checked unchanged.
This file is not an apply script; do not replace its rollback with commit without
separate review and authorization. The reconciliation documentation below describes
the separate `001_*` artifacts and does not authorize executing them for this cleanup.

Status: prepared for review; NOT applied. No PostgreSQL connection was opened during preparation.

## Deployment strategy and scope

Use explicit, versioned, reviewed SQL deployment artifacts. Normal API startup must never
perform schema changes or package-data backfills. This reconciliation is deliberately
NOT appended to the unresolved EF migration chain and is NOT a fresh-database script.

`001_reconcile.sql` adds only:

- The confirmed missing FKs from `PhotographyPackageServices(PhotographyPackageId)` to
  `PhotographyPackages(Id)` and from `PhotographyPackageServices(StudioServiceId)` to
  `StudioServices(Id)`, each only when absent and orphan-free after validation.
- The confirmed missing non-unique B-tree index on `PhotographyPackageServices(StudioServiceId)`,
  only if no equivalent valid/ready index exists and no incompatible candidate/name collision exists.
- `public.Users.PhoneNumber character varying(30) NULL`.
- `public.Users.ProfilePhotoUrl character varying(2048) NULL`.
- `Bookings`, `BookingLocations`, `BookingStatusHistories`, `Reviews`, `Notifications`.
- The five tables' current-model primary keys, alternate key, foreign keys, indexes,
  and review rating check constraint.

Bookings are created directly with `CustomerId integer`, `StudioId uuid`, `PackageId uuid`,
and nullable `PricingSnapshotJson jsonb`. No obsolete integer relationship is created or converted.
All other columns, nullability, identity generation, and precision come from the current
`ApplicationDbContext` model using the project's EF/Npgsql SQL generator.
CLR property initializers are not invented as database defaults.

The only existing package/service schema additions permitted are those two missing FKs and
the missing StudioServiceId index.
No existing Studio, Package, Portfolio, Service, Availability, or join table is replaced. No existing row, ID, password hash, price, or relationship is updated.
No INSERT/UPDATE/DELETE/TRUNCATE/DROP statements are issued. `ON DELETE` clauses define
the current model's future referential behavior; they do not delete data during reconciliation.

## Review artifacts

- `001_reconcile.sql`: complete transactional apply artifact, including preflight.
- `001_preflight.sql`: the same preflight in a read-only transaction, ending in rollback.
- `current-model.json`: current model's table/column/key/FK/index/check inventory.
- `../../tools/SchemaReconciliation/`: offline generator and preflight template.

The generator does not start the API, load its settings/secrets, call migrations, or open
a database connection. It has no apply mode and rejects connection attempts through an interceptor.
It uses the current model, not the historical snapshot. `--verify` detects artifact drift.

From the `backend` directory, with .NET SDK 8 or newer:

```powershell
dotnet run --project tools/SchemaReconciliation/SchemaReconciliation.csproj --artifacts-path .reconciliation-build -- --generate database/reconciliation
dotnet run --project tools/SchemaReconciliation/SchemaReconciliation.csproj --artifacts-path .reconciliation-build -- --verify database/reconciliation
powershell -NoProfile -File database/reconciliation/Verify-Artifacts.ps1
```

These commands only build/generate/verify local artifacts. They do not execute SQL.
Review regenerated files before deployment; after deployment freeze this numbered artifact
and make any future schema change a new reviewed script.

## Preconditions and conflict policy

The script targets the `public` schema explicitly. It requires:

1. All nine existing model tables are permanent ordinary tables.
2. Every mapped existing column has the current model's type and nullability; keys,
   FKs (including delete action), and indexes already match their model definitions,
   except for the two explicitly approved missing package/service FKs and StudioServiceId index.
   Keys and indexes are matched structurally, so manually named equivalent objects work.
3. `Users.Id` already has identity/sequence generation.
4. The two new User columns and all five new tables are absent. An already-present
   target is a conflict, even if empty or apparently compatible. Reruns stop safely.
5. `__EFMigrationsHistory` contains exactly the confirmed
   `202609020001_AddPortfolioImages` entry. Any other history requires review.
6. No conflicting target type, index, identity-sequence name, or same-name table in
   another user schema exists.

Existing unmapped legacy columns (for example `Studios.ProfileImage`) and existing
defaults are left untouched. They do not replace or relax checks on mapped columns.
The only missing-constraint exceptions are:
- `PhotographyPackageServices(PhotographyPackageId) -> PhotographyPackages(Id)`.
- `PhotographyPackageServices(StudioServiceId) -> StudioServices(Id)`.

The user reported live read-only results of 2 join rows, 0 orphans for each relationship,
correct UUID NOT NULL columns and primary keys, and neither FK present. These counts are
evidence, not hardcoded assumptions. All other missing/incompatible constraints still stop; the one index exception is described below.

Both artifacts validate all existing tables/columns/keys/indexes before the special FK checks.
For each relationship, candidates include constraints with the expected name, or FKs referencing
the respective parent, using the respective child column, or carrying the relationship's name
prefix. Every candidate must match the exact single-column relationship, CASCADE deletion,
NO ACTION updates, MATCH SIMPLE, validated and NOT DEFERRABLE/initially immediate status.
Any incompatible candidate stops, even alongside a compatible FK. Equivalent FKs under other
names are accepted without duplication. Target constraint-name collisions stop.

Both orphan counts use NOT EXISTS; either nonzero count stops without repairing/deleting data.
Both relationships' checks finish before either FK can be created. Read-only preflight reports
each absent FK as required and ends with ROLLBACK. Apply repeats checks under table locks and
creates only absent FKs, fully validated (no NOT VALID), with explicit MATCH SIMPLE ON UPDATE
NO ACTION ON DELETE CASCADE NOT DEFERRABLE. Existing package/service rows and prices remain
untouched, including the 2 confirmed join rows. Any failure rolls back the whole transaction.

The user also confirmed that the only join-table index is the valid/ready composite primary-key
index `PhotographyPackageServices_pkey(PhotographyPackageId, StudioServiceId)` and the separate
StudioServiceId index is missing. That composite PK remains unchanged and is not equivalent.
The index exception requires exactly one key column, StudioServiceId, a non-unique valid/ready
B-tree, no expressions/filter and default ordering. Key comparison uses `indnkeyatts`, so INCLUDE
columns are allowed without being counted as keys. An equivalent index under any name is retained.
An incompatible single-key StudioServiceId index or target relation/type-name collision stops,
even if another equivalent index exists. Other differently keyed indexes are left untouched.
These checks run after structural/FK/orphan checks and before any conditional DDL. Only the apply
artifact can conditionally create `IX_PhotographyPackageServices_StudioServiceId`; read-only
preflight only reports it. The existing primary key and every existing row remain untouched.

Preparation remains offline. Rerun the updated read-only preflight against the live database
before reviewing any application; earlier inspection is not a substitute for these new checks.

## Applying later — NOT authorized/executed during preparation

First review the SQL and preflight results, verify a recoverable backup, and arrange a
maintenance window. Stop old application instances before applying: an already-running
old executable does not acquire the new startup behavior until redeployed. No process
was stopped or restarted during preparation.

Use a dedicated libpq service named `snapsync_reconciliation` pointing to the reviewed
existing database. Set its host/database/user outside the repository and use a protected
password file or interactive password prompt. Never put a password in the command line.

From `backend`, the read-only check WOULD be:

```powershell
psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname='service=snapsync_reconciliation' --file='database/reconciliation/001_preflight.sql'
```

After separate approval, the exact apply command WOULD be:

```powershell
psql --no-psqlrc --set=ON_ERROR_STOP=1 --dbname='service=snapsync_reconciliation' --file='database/reconciliation/001_reconcile.sql'
```

Do not run either command as part of offline verification. `psql` must be installed and
the service configured first. There is no default target database in these artifacts.

The apply script owns one transaction, obtains an advisory transaction lock, locks existing
tables before rechecking prerequisites, and uses a 5-second lock timeout and 60-second
statement timeout. `ON_ERROR_STOP` prevents continuing after a failure; connection closure
rolls back the aborted transaction. Do not add an outer `--single-transaction` wrapper.
There is no destructive Down script. After successful application, use forward-only,
separately reviewed corrections if needed. Preserve the approved SQL/checksum and execution
result in the deployment record; this script does not create a ledger table or modify EF history.

## Legacy isolation and future changes

`PhotographyBooking.Api.csproj` excludes `Migrations/**/*.cs` from compilation. Original
migration source, designers, and the stale snapshot remain unchanged as historical evidence.
The generator asserts that the API assembly exposes no runnable EF migrations.
`Program.cs` no longer calls `Database.Migrate()` or executes any startup DDL/backfill SQL.
No `EnsureCreated()` call was found in the API source.

Never run `dotnet ef database update`, use `EnsureCreated`, re-enable the archived chain,
or insert fake history entries to make legacy migrations look applied. The existing history
row remains exactly as it was. Use controlled reviewed SQL for subsequent deployments.
If a new EF migration chain is desired later, first verify the complete live model and
design a separate baseline/assembly/history strategy; do not reuse the stale snapshot.

This preparation does not change runtime database permissions. The deployed application
role should not need DDL privileges; changing those grants is a separate administrative action.

## Validation limits

Offline generation, current-model consistency checks, legacy migration isolation, and SQL
scope checks are available here. Neither SQL script has been executed against PostgreSQL.
Database syntax/catalog execution and live preconditions still need validation before approval
to apply. No authentication, frontend, mobile, or AI feature changes are included.

References: [EF reviewed SQL deployment](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying),
[psql error handling](https://www.postgresql.org/docs/current/app-psql.html).
