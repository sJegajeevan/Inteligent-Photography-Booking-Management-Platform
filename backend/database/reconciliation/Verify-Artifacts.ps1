$ErrorActionPreference = 'Stop'

# Static safety checks only. Never invokes psql or starts the API.
$sql = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '001_reconcile.sql'))
$preflight = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '001_preflight.sql'))
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../tools/SchemaReconciliation/preflight.sql'))
foreach ($artifact in @($sql, $preflight, $template)) {
    if ($artifact -notmatch 'i\.indnkeyatts = cardinality\(expected_columns\)' -or
        $artifact -notmatch '(?s)unnest\(i\.indkey\).*?WHERE k\.pos <= i\.indnkeyatts ORDER BY k\.pos\) = expected_columns') {
        throw 'Index comparison must compare only actual key columns, excluding INCLUDE columns.'
    }
}
$expectedTables = @('Bookings', 'BookingLocations', 'BookingStatusHistories', 'Reviews', 'Notifications') | Sort-Object
$actualTables = [regex]::Matches($sql, '(?m)^CREATE TABLE public\."([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object
if (@(Compare-Object $expectedTables $actualTables).Count -ne 0) { throw 'CREATE TABLE scope differs.' }
$alterLines = [regex]::Matches($sql, '(?m)^\s*ALTER TABLE[^\r\n]+') | ForEach-Object { $_.Value.Trim() }
$expectedAlter = @(
    'ALTER TABLE public."Studios" ALTER COLUMN "UserId" SET NOT NULL;',
    'ALTER TABLE public."Studios" ADD CONSTRAINT "FK_Studios_Users_UserId" FOREIGN KEY ("UserId") REFERENCES public."Users" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;', 
    'ALTER TABLE public."StudioServices" ALTER COLUMN "StudioId" SET NOT NULL;',
    'ALTER TABLE public."StudioServices" ADD CONSTRAINT "FK_StudioServices_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;',
    'ALTER TABLE public."StudioPortfolios" ALTER COLUMN "StudioId" SET NOT NULL;',
    'ALTER TABLE public."StudioPortfolios" ADD CONSTRAINT "FK_StudioPortfolios_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;',
    'ALTER TABLE public."StudioAvailabilities" ALTER COLUMN "StudioId" SET NOT NULL;',
    'ALTER TABLE public."StudioAvailabilities" ADD CONSTRAINT "FK_StudioAvailabilities_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;',
    'ALTER TABLE public."PhotographyPackages" ADD CONSTRAINT "FK_PhotographyPackages_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;',
    'ALTER TABLE public."Users" ADD "PhoneNumber" character varying(30);',
    'ALTER TABLE public."Users" ADD "ProfilePhotoUrl" character varying(2048);',
    'ALTER TABLE public."PhotographyPackageServices" ADD CONSTRAINT "FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~" FOREIGN KEY ("PhotographyPackageId") REFERENCES public."PhotographyPackages" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;',
    'ALTER TABLE public."PhotographyPackageServices" ADD CONSTRAINT "FK_PhotographyPackageServices_StudioServices_StudioServiceId" FOREIGN KEY ("StudioServiceId") REFERENCES public."StudioServices" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;'
)
if (@(Compare-Object $expectedAlter $alterLines).Count -ne 0) { throw 'ALTER TABLE scope differs.' }
if (($sql.Replace('DROP INDEX public."IX_Studios_UserId" RESTRICT;', '')) -match '(?im)^\s*(DROP|TRUNCATE|DELETE|UPDATE|INSERT|MERGE|GRANT|REVOKE)\b') { throw 'Forbidden data/destructive operation.' }
if ($sql -match '(?im)^\s*(CREATE|ALTER)[^\r\n]*IF NOT EXISTS') { throw 'Reconciliation must not silently skip conflicting targets.' }
if ($sql -notmatch '"StudioId" uuid NOT NULL' -or $sql -notmatch '"PackageId" uuid NOT NULL' -or
    $sql -notmatch '"PricingSnapshotJson" jsonb,' -or $sql -match '"PricingSnapshotJson" jsonb NOT NULL') { throw 'Booking types differ.' }
if ([regex]::Matches($sql, '(?m)^\s+CONSTRAINT "FK_').Count -ne 10) { throw 'Expected 10 foreign keys.' }
if ([regex]::Matches($sql, '(?m)^\s*CREATE (UNIQUE )?INDEX ').Count -ne 14) { throw 'Expected 12 new-table indexes, 1 guarded service index and 1 ownership replacement index.' }
if ([regex]::Matches($sql, '(?m)^CREATE UNIQUE INDEX ').Count -ne 3) { throw 'Expected 3 unique indexes.' }
if ([regex]::Matches($sql, '(?m)^\s+CONSTRAINT "PK_').Count -ne 5) { throw 'Expected 5 primary keys.' }
if ($sql -notmatch 'CONSTRAINT "AK_Bookings_Id_CustomerId_StudioId" UNIQUE' -or
    $sql -notmatch 'CONSTRAINT "CK_Reviews_Rating" CHECK \("Rating" BETWEEN 1 AND 5\)') { throw 'Required constraints missing.' }
if ($sql.IndexOf('DO $reconciliation$') -gt $sql.IndexOf('ALTER TABLE public.') -or
    $sql -notmatch '(?m)^BEGIN;' -or $sql -notmatch '(?m)^COMMIT;' -or
    $sql -notmatch 'pg_advisory_xact_lock' -or $sql -notmatch 'lock_timeout') { throw 'Transaction/preflight protection missing.' }
if ($preflight -notmatch 'SET TRANSACTION READ ONLY;' -or $preflight -notmatch '(?m)^ROLLBACK;' -or
    $preflight -match '(?im)^\s*(CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|TRUNCATE)\b') { throw 'Preflight must remain read-only.' }
$api = Join-Path $PSScriptRoot '../../PhotographyBooking.Api'
$startup = [IO.File]::ReadAllText((Join-Path $api 'Program.cs'))
if ($startup -match 'EnsureCreated\s*\(|\.Migrate\s*\(|ExecuteSql') { throw 'Startup database mutation detected.' }
[xml]$project = [IO.File]::ReadAllText((Join-Path $api 'PhotographyBooking.Api.csproj'))
$excludedSources = @($project.SelectNodes('/Project/ItemGroup/Compile') | ForEach-Object { $_.GetAttribute('Remove') })
if ('Migrations/**/*.cs' -notin $excludedSources) { throw 'Legacy migrations are not isolated.' }
Write-Output 'PASS: additive scope, UUID/jsonb fields, constraints, transaction/preflight, read-only checks, and startup/legacy isolation. No SQL executed.'

# The exact missing-FK exception must keep all guards in both generated variants.
foreach ($artifact in @($sql, $preflight)) {
    foreach ($guard in @(
        "package_fk.contype = 'f' AND package_fk.convalidated",
        'AND NOT package_fk.condeferrable AND NOT package_fk.condeferred',
        "package_fk.confdeltype = 'c' AND package_fk.confupdtype = 'a'",
        "package_fk.confmatchtype = 's'",
        'a.attnum = ANY(c.conkey)',
        "starts_with(c.conname::text, 'FK_PhotographyPackageServices_PhotographyPackages_')",
        'IF orphan_count <> 0 THEN',
        'IF NOT package_fk_present THEN',
        'Incompatible package-service FK or constraint name collision',
        'Stop; never delete or repair data automatically.'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing package FK guard: $guard" }
    }
    if ($artifact.Contains('__PACKAGE_FK_DDL__')) { throw 'Unexpanded FK DDL placeholder.' }
}
$fkDdlPosition = $sql.IndexOf('ALTER TABLE public."PhotographyPackageServices"')
if ($fkDdlPosition -lt $sql.IndexOf('IF NOT package_fk_present THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('IF orphan_count <> 0 THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('Incompatible package-service FK or constraint name collision') -or
    $sql.IndexOf('LOCK TABLE public."PhotographyPackages"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Package FK creation must follow locks and all conflict/orphan/absence guards.'
}
$model = Get-Content (Join-Path $PSScriptRoot 'current-model.json') -Raw | ConvertFrom-Json
$exceptions = @($model.tables | ForEach-Object {
    $tableName = $_.name
    $_.foreignKeys | Where-Object { $_.reconcileWhenMissing } | ForEach-Object {
        "$tableName.$($_.name)"
    }
})
$expectedExceptions = @(
    'Studios.FK_Studios_Users_UserId',
    'StudioServices.FK_StudioServices_Studios_StudioId',
    'StudioPortfolios.FK_StudioPortfolios_Studios_StudioId',
    'StudioAvailabilities.FK_StudioAvailabilities_Studios_StudioId',
    'PhotographyPackages.FK_PhotographyPackages_Studios_StudioId',
    'PhotographyPackageServices.FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~',
    'PhotographyPackageServices.FK_PhotographyPackageServices_StudioServices_StudioServiceId'
)
if ($exceptions.Count -ne 7 -or @(Compare-Object $expectedExceptions $exceptions).Count -ne 0) {
    throw 'Only the seven approved package/service, package/studio, availability/studio portfolio/studio and service-owner FKs may be reconciled when missing.'
}
Write-Output 'PASS: exact missing package FK exception, incompatible-definition rejection, orphan guard, locked conditional DDL, synchronized scope. No SQL executed.'

foreach ($artifact in @($sql, $preflight)) {
    foreach ($guard in @(
        "service_fk.contype = 'f' AND service_fk.convalidated",
        'AND NOT service_fk.condeferrable AND NOT service_fk.condeferred',
        "service_fk.confdeltype = 'c' AND service_fk.confupdtype = 'a'",
        "service_fk.confmatchtype = 's'",
        "starts_with(c.conname::text, 'FK_PhotographyPackageServices_StudioServices_')",
        "ORDER BY k.pos) = ARRAY['StudioServiceId']::text[]",
        'IF service_orphan_count <> 0 THEN',
        'IF NOT service_fk_present THEN',
        'Incompatible studio-service FK or constraint name collision'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing studio-service FK guard: $guard" }
    }
    if ($artifact.Contains('__SERVICE_FK_DDL__')) { throw 'Unexpanded service FK placeholder.' }
}
$serviceDdlPosition = $sql.IndexOf('ALTER TABLE public."PhotographyPackageServices" ADD CONSTRAINT "FK_PhotographyPackageServices_StudioServices_StudioServiceId"')
if ($serviceDdlPosition -lt $sql.IndexOf('IF NOT service_fk_present THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('IF service_orphan_count <> 0 THEN') -or
    $serviceDdlPosition -lt $sql.IndexOf('Incompatible studio-service FK or constraint name collision') -or
    $sql.IndexOf('LOCK TABLE public."StudioServices"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Both FK checks must precede any FK creation; StudioServices must be locked.'
}
Write-Output 'PASS: both approved missing FKs checked before conditional creation; StudioService conflict/orphan guards and read-only preflight. No SQL executed.'

$expectedIndexDdl = 'CREATE INDEX "IX_PhotographyPackageServices_StudioServiceId" ON public."PhotographyPackageServices" USING btree ("StudioServiceId");'
if ([regex]::Matches($sql, [regex]::Escape($expectedIndexDdl)).Count -ne 1) {
    throw 'Expected exactly one approved StudioServiceId index creation.'
}
foreach ($artifact in @($sql, $preflight)) {
    foreach ($guard in @(
        'IF NOT service_index_present THEN',
        'IF NOT service_index.compatible THEN',
        'i.indnkeyatts = 1',
        'AND NOT i.indisunique AND i.indexprs IS NULL AND i.indpred IS NULL',
        "WHERE k.pos <= i.indnkeyatts ORDER BY k.pos) = ARRAY['StudioServiceId']::text[]",
        "ns.nspname = 'public' AND ic.relname = 'IX_PhotographyPackageServices_StudioServiceId'",
        'Incompatible StudioServiceId index or relation name collision',
        'StudioServiceId index target type-name collision'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing service index guard: $guard" }
    }
    if ($artifact.Contains('__SERVICE_INDEX_DDL__')) { throw 'Unexpanded index placeholder.' }
}
$indexDdlPosition = $sql.IndexOf($expectedIndexDdl)
if ($indexDdlPosition -lt $sql.IndexOf('IF NOT service_index_present THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('StudioServiceId index target type-name collision') -or
    $sql.IndexOf('LOCK TABLE public."PhotographyPackageServices"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Index checks must precede all conditional DDL under table locks.'
}
$indexExceptions = @($model.tables | ForEach-Object {
    $tableName = $_.name
    $_.indexes | Where-Object { $_.reconcileWhenMissing } | ForEach-Object { "$tableName.$($_.name)" }
})
if ($indexExceptions.Count -ne 1 -or $indexExceptions[0] -ne 'PhotographyPackageServices.IX_PhotographyPackageServices_StudioServiceId') {
    throw 'Only the approved service index may be reconciled when missing.'
}
Write-Output 'PASS: exact conditional service index, name collisions, single key excluding INCLUDE, preserved PK and both FK exceptions. No SQL executed.'

foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "object_name = 'PhotographyPackages' AND",
        "item->>'name' = 'FK_PhotographyPackages_Studios_StudioId' AND",
        "studio_fk.contype = 'f' AND studio_fk.convalidated",
        'AND NOT studio_fk.condeferrable AND NOT studio_fk.condeferred',
        "coalesce((to_jsonb(studio_fk)->>'conenforced')::boolean, true)",
        "studio_fk.confdeltype = 'c' AND studio_fk.confupdtype = 'a'",
        "studio_fk.confmatchtype = 's'",
        "ORDER BY key_col.pos) = ARRAY['StudioId']::text[]",
        "ORDER BY key_col.pos) = ARRAY['Id']::text[]",
        'key_index.indisunique AND key_index.indisvalid AND key_index.indisready',
        'key_index.indislive AND key_index.indimmediate',
        'key_index.indpred IS NULL AND key_index.indexprs IS NULL',
        'IF studio_null_count <> 0 THEN',
        'IF studio_orphan_count <> 0 THEN',
        'IF NOT studio_fk_present THEN',
        'Incompatible package-studio FK or constraint name collision'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing package-studio guard: $guard" }
    }
}
foreach ($artifact in @($sql, $preflight)) {
    if ($artifact.Contains('__STUDIO_FK_DDL__')) { throw 'Unexpanded studio FK placeholder.' }
}
$studioDdlPosition = $sql.IndexOf('ALTER TABLE public."PhotographyPackages" ADD CONSTRAINT')
if ($studioDdlPosition -lt $sql.IndexOf('IF NOT studio_fk_present THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('IF studio_null_count <> 0 THEN') -or
    $fkDdlPosition -lt $sql.IndexOf('IF studio_orphan_count <> 0 THEN') -or
    $studioDdlPosition -lt $sql.IndexOf('StudioServiceId index target type-name collision') -or
    $sql.IndexOf('LOCK TABLE public."Studios"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Package-studio validation must precede all DDL, with absence guard and Studios lock.'
}
Write-Output 'PASS: exact package-studio exception, eligible parent key, null/orphan guards, incompatible FK rejection, equivalent-name handling and conditional DDL. No SQL executed.'

$nullabilityExceptions = @($model.tables | ForEach-Object {
    $tableName = $_.name
    $_.columns | Where-Object { $_.reconcileNotNull } | ForEach-Object {
        if ($_.type -ne $(if ($tableName -eq 'Studios') { 'integer' } else { 'uuid' }) -or $_.nullable) { throw 'NOT NULL exception requires a required UUID in the model.' }
        "$tableName.$($_.name)"
    }
})
if ($nullabilityExceptions.Count -ne 4 -or @(Compare-Object @('StudioAvailabilities.StudioId', 'StudioPortfolios.StudioId', 'StudioServices.StudioId', 'Studios.UserId') $nullabilityExceptions).Count -ne 0) {
    throw 'Only StudioAvailabilities.StudioId, StudioPortfolios.StudioId and StudioServices.StudioId may have approved NOT NULL transitions.'
}
foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "object_name = 'StudioAvailabilities' AND item->>'name' = 'StudioId'",
        "coalesce((item->>'reconcileNotNull')::boolean, false)",
        "column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''",
        "column_record.attidentity <> ''",
        'availability_not_null_required := NOT column_record.attnotnull;',
        'AND availability_not_null_required',
        "item->>'name' = 'FK_StudioAvailabilities_Studios_StudioId' AND",
        "availability_fk.contype = 'f' AND availability_fk.convalidated",
        'AND NOT availability_fk.condeferrable AND NOT availability_fk.condeferred',
        "coalesce((to_jsonb(availability_fk)->>'conenforced')::boolean, true)",
        "availability_fk.confdeltype = 'c' AND availability_fk.confupdtype = 'a'",
        "availability_fk.confmatchtype = 's'",
        "starts_with(constraint_row.conname::text, 'FK_StudioAvailabilities_Studios_')",
        'Incompatible availability-studio FK or constraint name collision',
        'IF availability_null_count <> 0 THEN',
        'IF availability_orphan_count <> 0 THEN',
        'IF availability_not_null_required THEN',
        'IF NOT availability_fk_present THEN'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing availability guard: $guard" }
    }
}
foreach ($artifact in @($sql, $preflight)) {
    if ($artifact -match '__AVAILABILITY_(NOT_NULL|FK)_DDL__') { throw 'Unexpanded availability placeholder.' }
}
$notNullDdl = 'ALTER TABLE public."StudioAvailabilities" ALTER COLUMN "StudioId" SET NOT NULL;'
$availabilityDdlPosition = $sql.IndexOf('ALTER TABLE public."StudioAvailabilities" ADD CONSTRAINT')
if ([regex]::Matches($sql, [regex]::Escape($notNullDdl)).Count -ne 1 -or
    $sql.IndexOf($notNullDdl) -lt $sql.IndexOf('IF availability_not_null_required THEN') -or
    $availabilityDdlPosition -lt $sql.IndexOf($notNullDdl) -or
    $availabilityDdlPosition -lt $sql.IndexOf('IF NOT availability_fk_present THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF availability_null_count <> 0 THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF availability_orphan_count <> 0 THEN') -or
    $sql.IndexOf('LOCK TABLE public."StudioAvailabilities"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Availability data/structure checks must precede all DDL; conditional NOT NULL must precede its FK under locks.'
}
Write-Output 'PASS: exact availability UUID NOT NULL transition and FK, no backfill, unchanged required model, all guards before DDL and read-only preflight. No SQL executed.'

foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "object_name = 'StudioPortfolios' AND item->>'name' = 'StudioId'",
        "coalesce((item->>'reconcileNotNull')::boolean, false)",
        "column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''",
        "column_record.attidentity <> ''",
        'portfolio_not_null_required := NOT column_record.attnotnull;',
        'AND portfolio_not_null_required',
        "item->>'name' = 'FK_StudioPortfolios_Studios_StudioId' AND",
        "portfolio_fk.contype = 'f' AND portfolio_fk.convalidated",
        'AND NOT portfolio_fk.condeferrable AND NOT portfolio_fk.condeferred',
        "coalesce((to_jsonb(portfolio_fk)->>'conenforced')::boolean, true)",
        "portfolio_fk.confdeltype = 'c' AND portfolio_fk.confupdtype = 'a'",
        "portfolio_fk.confmatchtype = 's'",
        "starts_with(constraint_row.conname::text, 'FK_StudioPortfolios_Studios_')",
        'Incompatible portfolio-studio FK or constraint name collision',
        'IF portfolio_null_count <> 0 THEN',
        'IF portfolio_orphan_count <> 0 THEN',
        'IF portfolio_not_null_required THEN',
        'IF NOT portfolio_fk_present THEN'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing portfolio guard: $guard" }
    }
}
foreach ($artifact in @($sql, $preflight)) {
    if ($artifact -match '__PORTFOLIO_(NOT_NULL|FK)_DDL__') { throw 'Unexpanded portfolio placeholder.' }
}
$notNullDdl = 'ALTER TABLE public."StudioPortfolios" ALTER COLUMN "StudioId" SET NOT NULL;'
$portfolioDdlPosition = $sql.IndexOf('ALTER TABLE public."StudioPortfolios" ADD CONSTRAINT')
if ([regex]::Matches($sql, [regex]::Escape($notNullDdl)).Count -ne 1 -or
    $sql.IndexOf($notNullDdl) -lt $sql.IndexOf('IF portfolio_not_null_required THEN') -or
    $portfolioDdlPosition -lt $sql.IndexOf($notNullDdl) -or
    $portfolioDdlPosition -lt $sql.IndexOf('IF NOT portfolio_fk_present THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF portfolio_null_count <> 0 THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF portfolio_orphan_count <> 0 THEN') -or
    $sql.IndexOf('LOCK TABLE public."StudioPortfolios"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Portfolio data/structure checks must precede all DDL; conditional NOT NULL must precede its FK under locks.'
}
Write-Output 'PASS: exact portfolio UUID NOT NULL transition and FK, no backfill, unchanged required model, all guards before DDL and read-only preflight. No SQL executed.'

foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "object_name = 'StudioServices' AND item->>'name' = 'StudioId'",
        "coalesce((item->>'reconcileNotNull')::boolean, false)",
        "column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''",
        "column_record.attidentity <> ''",
        'serviceOwner_not_null_required := NOT column_record.attnotnull;',
        'AND serviceOwner_not_null_required',
        "item->>'name' = 'FK_StudioServices_Studios_StudioId' AND",
        "serviceOwner_fk.contype = 'f' AND serviceOwner_fk.convalidated",
        'AND NOT serviceOwner_fk.condeferrable AND NOT serviceOwner_fk.condeferred',
        "coalesce((to_jsonb(serviceOwner_fk)->>'conenforced')::boolean, true)",
        "serviceOwner_fk.confdeltype = 'c' AND serviceOwner_fk.confupdtype = 'a'",
        "serviceOwner_fk.confmatchtype = 's'",
        "starts_with(constraint_row.conname::text, 'FK_StudioServices_Studios_')",
        'Incompatible serviceOwner-studio FK or constraint name collision',
        'IF serviceOwner_null_count <> 0 THEN',
        'IF serviceOwner_orphan_count <> 0 THEN',
        'IF serviceOwner_not_null_required THEN',
        'IF NOT serviceOwner_fk_present THEN'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing serviceOwner guard: $guard" }
    }
}
foreach ($artifact in @($sql, $preflight)) {
    if ($artifact -match '__SERVICE_OWNER_(NOT_NULL|FK)_DDL__') { throw 'Unexpanded serviceOwner placeholder.' }
}
$notNullDdl = 'ALTER TABLE public."StudioServices" ALTER COLUMN "StudioId" SET NOT NULL;'
$serviceOwnerDdlPosition = $sql.IndexOf('ALTER TABLE public."StudioServices" ADD CONSTRAINT')
if ([regex]::Matches($sql, [regex]::Escape($notNullDdl)).Count -ne 1 -or
    $sql.IndexOf($notNullDdl) -lt $sql.IndexOf('IF serviceOwner_not_null_required THEN') -or
    $serviceOwnerDdlPosition -lt $sql.IndexOf($notNullDdl) -or
    $serviceOwnerDdlPosition -lt $sql.IndexOf('IF NOT serviceOwner_fk_present THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF serviceOwner_null_count <> 0 THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('IF serviceOwner_orphan_count <> 0 THEN') -or
    $sql.IndexOf('LOCK TABLE public."StudioServices"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'ServiceOwner data/structure checks must precede all DDL; conditional NOT NULL must precede its FK under locks.'
}
Write-Output 'PASS: exact serviceOwner UUID NOT NULL transition and FK, no backfill, unchanged required model, all guards before DDL and read-only preflight. No SQL executed.'

$ownershipCreate = 'CREATE UNIQUE INDEX "IX_Studios_UserId_reconciliation" ON public."Studios" USING btree ("UserId");'
$ownershipDrop = 'DROP INDEX public."IX_Studios_UserId" RESTRICT;'
$ownershipRename = 'ALTER INDEX public."IX_Studios_UserId_reconciliation" RENAME TO "IX_Studios_UserId";'
$ownershipNotNull = 'ALTER TABLE public."Studios" ALTER COLUMN "UserId" SET NOT NULL;'
foreach ($statement in @($ownershipCreate, $ownershipDrop, $ownershipRename, $ownershipNotNull)) {
    if ([regex]::Matches($sql, [regex]::Escape($statement)).Count -ne 1) { throw "Expected one exact ownership operation: $statement" }
}
$indexAlters = @([regex]::Matches($sql, '(?m)^\s*ALTER INDEX[^\r\n]+') | ForEach-Object { $_.Value.Trim() })
if ($indexAlters.Count -ne 1 -or $indexAlters[0] -ne $ownershipRename) { throw 'Unexpected ALTER INDEX scope.' }
$partialExceptions = @($model.tables | ForEach-Object {
    $tableName = $_.name
    $_.indexes | Where-Object { $_.reconcileKnownPartial } | ForEach-Object { "$tableName.$($_.name)" }
})
if ($partialExceptions.Count -ne 1 -or $partialExceptions[0] -ne 'Studios.IX_Studios_UserId') {
    throw 'Only the known ownership index may be replaced.'
}
foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "object_name = 'Studios' AND item->>'name' = 'UserId'",
        "column_record.type_name <> 'integer' OR column_record.attgenerated <> ''",
        'ownership_not_null_required := NOT column_record.attnotnull;',
        "ownership_fk.contype = 'f' AND ownership_fk.convalidated",
        'AND NOT ownership_fk.condeferrable AND NOT ownership_fk.condeferred',
        "coalesce((to_jsonb(ownership_fk)->>'conenforced')::boolean, true)",
        "ownership_fk.confdeltype = 'c' AND ownership_fk.confupdtype = 'a'",
        "ownership_fk.confmatchtype = 's'",
        "ORDER BY key_col.pos) = ARRAY['UserId']::text[]",
        'Users.Id lacks a valid eligible PK/unique key',
        'IF ownership_null_count <> 0 THEN', 'IF ownership_orphan_count <> 0 THEN',
        'IF ownership_duplicate_count <> 0 THEN',
        'IF NOT ownership_index.compatible_base THEN',
        "ownership_index.relname = 'IX_Studios_UserId'",
        'ownership_index.predicate_sql IN (',
        'idx.indnkeyatts = 1 AND idx.indnatts = 1',
        'idx.indisunique AND idx.indisvalid AND idx.indisready',
        'idx.indislive AND idx.indimmediate',
        'opclass.opcdefault',
        'dep.refobjid = ownership_index.oid',
        'Ownership replacement index name/type collision',
        'IF ownership_not_null_required THEN',
        'IF ownership_index_replace THEN', 'IF NOT ownership_fk_present THEN'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing ownership guard: $guard" }
    }
}
foreach ($artifact in @($sql, $preflight)) {
    if ($artifact -match '__OWNERSHIP_\w+_DDL__') { throw 'Unexpanded ownership placeholder.' }
}
if ($sql.IndexOf($ownershipCreate) -lt $sql.IndexOf($ownershipNotNull) -or
    $sql.IndexOf($ownershipDrop) -lt $sql.IndexOf($ownershipCreate) -or
    $sql.IndexOf($ownershipRename) -lt $sql.IndexOf($ownershipDrop) -or
    $sql.IndexOf($ownershipCreate) -lt $sql.IndexOf('IF ownership_index_replace THEN') -or
    $sql.IndexOf('ALTER TABLE public.') -lt $sql.IndexOf('Ownership replacement index name/type collision') -or
    $sql.IndexOf('LOCK TABLE public."Studios"') -gt $sql.IndexOf('DO $reconciliation$') -or
    $sql.IndexOf('LOCK TABLE public."Users"') -gt $sql.IndexOf('DO $reconciliation$')) {
    throw 'Ownership guards must precede all DDL; NOT NULL then CREATE UNIQUE then DROP RESTRICT then RENAME under locks.'
}
Write-Output 'PASS: ownership integer/NULL/orphan/duplicate/key/FK guards; exact partial-index replacement; continuous uniqueness; read-only preflight. No SQL executed.'

# Idempotency is driven by verified absence, never CREATE IF NOT EXISTS.
foreach ($artifact in @($sql, $preflight, $template)) {
    foreach ($guard in @(
        "IF (table_def->>'create')::boolean AND table_oid IS NULL THEN",
        'planned_tables := array_append(planned_tables, object_name);',
        "planned_user_columns := array_append(planned_user_columns, item->>'name');",
        'Exact target column set/order mismatch',
        'Exact target column semantics mismatch',
        "strict_column.attidentity::text IS DISTINCT FROM strict_item->>'identity'",
        "strict_column.default_sql IS DISTINCT FROM strict_item->>'defaultSql'",
        'Missing/incorrect target identity sequence', 'Incompatible target identity sequence',
        'Missing/unexpected target constraints', 'Incompatible target constraint state',
        'Incompatible target FK definition', 'Incompatible target CHECK definition',
        'Missing/unexpected target indexes', 'Incompatible target index',
        'Unexpected target table behavior', 'Incompatible already-present target column',
        'Already reconciled target public.% verified exactly; no creation planned.'
    )) {
        if (-not $artifact.Contains($guard)) { throw "Missing idempotency guard: $guard" }
    }
}
if ($sql.Contains('__TARGET_OBJECT_DDL__') -or $preflight.Contains('__TARGET_OBJECT_DDL__')) {
    throw 'Unexpanded target DDL placeholder.'
}
$conditionalTables = [regex]::Matches($sql, '(?m)^    IF ''([^'']+)'' = ANY\(planned_tables\) THEN\s*CREATE TABLE public\."\1"')
if ($conditionalTables.Count -ne 5) { throw 'Every target CREATE TABLE must be conditioned on the validated absent-table plan.' }
$conditionalIndexes = [regex]::Matches($sql, '(?m)^    IF ''([^'']+)'' = ANY\(planned_tables\) THEN\s*CREATE (?:UNIQUE )?INDEX "[^"]+" ON public\."\1"')
if ($conditionalIndexes.Count -ne 12) { throw 'All target indexes must only be created with their absent target table.' }
$conditionalColumns = [regex]::Matches($sql, '(?m)^    IF ''([^'']+)'' = ANY\(planned_user_columns\) THEN\s*ALTER TABLE public\."Users" ADD "\1"')
if ($conditionalColumns.Count -ne 2) { throw 'Both User additions must be guarded by verified absence.' }
$lastDoEnd = $sql.LastIndexOf('$reconciliation$;')
if ($sql.Substring($lastDoEnd) -match '(?im)^\s*(CREATE|ALTER|DROP)\b') { throw 'Unconditional DDL after reconciliation block.' }
if ($preflight.Contains('$target_locks$') -or $preflight -match '(?im)^\s*LOCK TABLE') { throw 'Read-only preflight must not acquire write-mode table locks.' }
foreach ($table in @($model.tables | Where-Object { $_.create })) {
    foreach ($column in $table.columns) {
        $expectedIdentity = if ($table.name -in @('Bookings','BookingLocations','BookingStatusHistories') -and $column.name -eq 'Id') { 'd' } else { '' }
        if ($column.identity -ne $expectedIdentity -or $column.generated -ne '' -or $null -ne $column.defaultSql) {
            throw "Unexpected target column semantics: $($table.name).$($column.name)"
        }
    }
}
$bookingsModel = $model.tables | Where-Object { $_.name -eq 'Bookings' }
$snapshotColumn = $bookingsModel.columns | Where-Object { $_.name -eq 'PricingSnapshotJson' }
$notificationModel = $model.tables | Where-Object { $_.name -eq 'Notifications' }
$bookingReference = $notificationModel.foreignKeys | Where-Object { $_.principalTable -eq 'Bookings' }
$reviewModel = $model.tables | Where-Object { $_.name -eq 'Reviews' }
if ($snapshotColumn.type -ne 'jsonb' -or -not $snapshotColumn.nullable -or
    -not ($notificationModel.columns | Where-Object { $_.name -eq 'BookingId' }).nullable -or
    $bookingReference.deleteAction -ne 'n' -or
    ($reviewModel.checks | Where-Object { $_.name -eq 'CK_Reviews_Rating' }).catalogSql -ne '(("Rating" >= 1) AND ("Rating" <= 5))') {
    throw 'Reconciled model jsonb/nullable notification FK/rating semantics changed.'
}
Write-Output 'PASS: absent-or-exact target validation, identity/default/check semantics, guarded target tables/indexes/User additions, rerun contains no unconditional DDL. No SQL executed.'
