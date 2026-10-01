# JourneyV1 constraint preparation

Prepared only. No SQL has been executed by this change. The live database must
remain on the legacy constraint until a separately authorized deployment.

`20260929000100_journey_v1_event_details.sql` replaces only
`public."AiWorkflowEvents"."CK_AiWorkflowEvents_Details"`. It preserves the exact
legacy branch for non-JourneyV1 events and adds the reviewed bounded JourneyV1
branch. It contains no event writes, table recreation, migrations, or changes to
other tables. The historical `ai-workflow` SQL is intentionally unchanged.

The expression between `$journey$` delimiters is identical to
`AiJourneyDetailsConstraint.Sql`, which `AiWorkflowConfiguration` now uses. The
expanded literal is intentional: reviewers can inspect the deployed CHECK and
offline tests can compare it byte-for-byte with EF's actual design-time model.
There is no database-dependent expression generation or application startup DDL.

## Offline verification

From the repository root:

```powershell
dotnet run --project backend/tests/AiJourneyChecks/AiJourneyChecks.csproj --configuration Release
dotnet build backend/PhotographyBooking.Api/PhotographyBooking.Api.csproj --configuration Release --no-restore
```

The check executable does not start the API, load application configuration or
secrets, or provide a connection string. Its connection interceptor rejects both
synchronous and asynchronous EF connection attempts. Only the two named SQL
files are embedded, never the backup or a directory wildcard.

Fixtures exercise a limited offline interpretation of the SQL's extracted scalar
regexes and variant key/stage predicates, plus model/deployment parity and
deployment guard checks. This is not a PostgreSQL interpreter. The byte-boundary
test supplies a measured-length value to test the extracted size gate; it does
not claim .NET reproduces PostgreSQL's JSONB text representation.

Before deployment, separately authorize a disposable PostgreSQL test for SQL
parsing, fixture inserts, JSONB byte accounting, repeated application, drift
refusal, transactional failure, and row-preserving rollback. Do not use the live
database or historical EF chain for those tests.

## Deployment properties and limits

- Transactional; five-second lock timeout and thirty-second statement timeout.
- Acquires ACCESS EXCLUSIVE on the event table, including during validation.
  Schedule an appropriate maintenance window; large-table validation may time out.
- Requires the existing validated, local constraint on a non-inherited ordinary
  table. Unexpected definitions or reserved constraint-name collisions abort.
- Uses two replacement-check names within the transaction to compare normalized
  PostgreSQL expressions. Neither remains after commit.
- Recognizes the exact legacy or prepared V2 expression. Reapplication to V2
  leaves the target constraint intact. All row contents are preserved.
- The legacy-to-V2 path refuses pre-existing use of the reserved JourneyV1 type.
- The 4,096-byte limit applies only to new JourneyV1 payloads. Legacy values are
  not retroactively tightened.
- Nine kinds: started, studio-option, package-option, schedule-option, completed,
  selected, validated, failed, rewound. Option lists contain 1–5 UUID references;
  safe explanation strings contain 1–300 characters.
- UUID existence/ownership, option uniqueness, real calendar dates, positive
  durations, error-code membership, and revision/concurrency rules remain future
  application validation requirements. This preparation does not add a writer,
  DTO endpoint, pause/resume behavior, or customer screens.
- The current package contract still allows only extra-hour customization, no
  add-ons, and zero additional photographers.

Once JourneyV1 rows exist, the legacy constraint cannot be restored while keeping
those rows valid. Roll back application behavior while retaining the additive
constraint; do not delete audit rows or leave an unvalidated legacy constraint.

The EF model intentionally represents the prepared target while the live schema
remains legacy. Do not regenerate the historical three-table artifact from this
model, run the historical migration chain, or automatically reconcile the model.

`photography_booking_before_ai_journey.backup` is private deployment material.
The existing repository `*.backup` ignore rule excludes it. Do not stage, embed,
modify, or include it in patches.
