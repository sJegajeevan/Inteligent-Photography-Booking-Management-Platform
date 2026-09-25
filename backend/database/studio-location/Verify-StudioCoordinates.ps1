param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Before', 'After')]
    [string]$Phase
)

$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $PSScriptRoot '../../PhotographyBooking.Api/appsettings.json'
$settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
$connection = New-Object System.Data.Common.DbConnectionStringBuilder
$connection.set_ConnectionString($settings.ConnectionStrings.DefaultConnection)
if ($connection.get_Item('Database') -ne 'photography_booking_db') {
    throw 'Configured database is not photography_booking_db; stop for review.'
}
$psql = 'C:/Program Files/PostgreSQL/18/bin/psql.exe'
$connectionArgs = @('-X', '-w', '-q', '-A', '-t', '--set=ON_ERROR_STOP=1',
    '-h', [string]$connection.get_Item('Host'), '-p', [string]$connection.get_Item('Port'),
    '-U', [string]$connection.get_Item('Username'), '-d', 'photography_booking_db')
$previousPassword = $env:PGPASSWORD
$previousTimeout = $env:PGCONNECT_TIMEOUT

function Read-Database([string]$Sql) {
    $queryFile = [System.IO.Path]::GetTempFileName()
    try {
        $readOnlySql = "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;`nSET LOCAL statement_timeout = '30s';`nSET LOCAL row_security = off;`n$Sql`nROLLBACK;`n"
        [System.IO.File]::WriteAllText($queryFile, $readOnlySql, (New-Object System.Text.UTF8Encoding($false)))
        $output = & $psql @connectionArgs --file $queryFile
        if ($LASTEXITCODE -ne 0) { throw "Read-only PostgreSQL verification failed (exit $LASTEXITCODE)." }
        return ($output -join "`n") | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $queryFile
    }
}

try {
    $env:PGPASSWORD = [string]$connection.get_Item('Password')
    $env:PGCONNECT_TIMEOUT = '5'
    $metadata = Read-Database @'
SELECT json_build_object(
  'database', current_database(),
  'tables', (SELECT json_agg(tablename ORDER BY tablename) FROM pg_tables WHERE schemaname = 'public'),
  'studioKind', (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relname = 'Studios'),
  'columns', (SELECT json_agg(c ORDER BY table_name, ordinal_position) FROM (
    SELECT table_name, column_name, data_type, udt_name, character_maximum_length,
      numeric_precision, numeric_scale, is_nullable, column_default, ordinal_position
    FROM information_schema.columns WHERE table_schema = 'public') c),
  'constraints', (SELECT json_agg(c ORDER BY table_name, name) FROM (
    SELECT rel.relname AS table_name, con.conname AS name, con.contype AS type,
      con.convalidated AS validated, pg_get_constraintdef(con.oid) AS definition
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = rel.relnamespace WHERE n.nspname = 'public') c),
  'coordinateExpression', (SELECT pg_get_expr(conbin, conrelid) FROM pg_constraint
    WHERE conrelid = 'public."Studios"'::regclass AND conname = 'CK_Studios_Coordinates'),
  'enabledEventTriggers', (SELECT count(*) FROM pg_event_trigger WHERE evtenabled <> 'D')
);
'@
    if ($metadata.database -ne 'photography_booking_db' -or $metadata.studioKind -ne 'r') {
        throw 'Database/table identity differs from the reviewed ordinary public.Studios table.'
    }
    if ($metadata.enabledEventTriggers -ne 0) { throw 'Enabled DDL event triggers require review before proceeding.' }
    $studioColumns = @($metadata.columns | Where-Object { $_.table_name -eq 'Studios' })
    $coordinates = @($studioColumns | Where-Object { $_.column_name -in @('Latitude', 'Longitude') })
    if ($Phase -eq 'Before') {
        $expected = @('Id', 'UserId', 'StudioName', 'Description', 'Location', 'ContactNumber', 'Email',
            'ProfileImage', 'Address', 'ExperienceYears', 'PhotographyTypes', 'StartingPrice', 'LogoUrl', 'CoverPhotoUrl')
        if ($coordinates.Count -ne 0 -or $metadata.coordinateExpression -or
            (Compare-Object ($expected | Sort-Object) ($studioColumns.column_name | Sort-Object))) {
            throw 'Studio schema differs from the reviewed 14-column baseline; stop.'
        }
    } else {
        if ($coordinates.Count -ne 2 -or @($coordinates | Where-Object {
            $_.data_type -ne 'numeric' -or $_.numeric_precision -ne 9 -or $_.numeric_scale -ne 6 -or
            $_.is_nullable -ne 'YES' -or $null -ne $_.column_default
        }).Count -ne 0) { throw 'Coordinate type/nullability/default verification failed.' }
        $constraint = @($metadata.constraints | Where-Object { $_.table_name -eq 'Studios' -and $_.name -eq 'CK_Studios_Coordinates' })
        if ($constraint.Count -ne 1 -or !$constraint[0].validated -or $constraint[0].type -ne 'c') {
            throw 'Validated coordinate check constraint is missing.'
        }
        # Evaluate the actual stored constraint against synthetic values only; no INSERT/UPDATE.
        $cases = @'
(VALUES
 (NULL::numeric,NULL::numeric,true), (0,0,true), (-90,-180,true), (90,180,true),
 (6.927079,79.861244,true), (NULL,0,false), (0,NULL,false), (-90.000001,0,false),
 (90.000001,0,false), (0,-180.000001,false), (0,180.000001,false),
 ('NaN'::numeric,0,false), (0,'NaN'::numeric,false)
) AS cases("Latitude","Longitude",expected)
'@
        $behavior = Read-Database ('SELECT json_build_object(''constraintCasesPassed'', bool_and((' +
            $metadata.coordinateExpression + ') IS NOT DISTINCT FROM expected), ''cases'', count(*)) FROM ' + $cases + ';')
        if (!$behavior.constraintCasesPassed) { throw 'Stored coordinate constraint failed boundary/pair tests.' }
        $nulls = Read-Database 'SELECT json_build_object(''allCoordinatesNull'', NOT EXISTS (SELECT 1 FROM public."Studios" WHERE "Latitude" IS NOT NULL OR "Longitude" IS NOT NULL));'
        if (!$nulls.allCoordinatesNull) { throw 'Unexpected populated coordinates; no backfill was authorized.' }
    }

    # Keep only aggregate fingerprints locally; never export account/customer data.
    $queries = foreach ($table in $metadata.tables) {
        $identifier = '"' + $table.Replace('"', '""') + '"'
        $label = "'" + $table.Replace("'", "''") + "'"
        $row = if ($table -eq 'Studios') { "to_jsonb(t) - 'Latitude' - 'Longitude'" } else { 'to_jsonb(t)' }
        "SELECT $label AS table_name, count(*) AS row_count, md5(coalesce(string_agg(md5(($row)::text), '' ORDER BY md5(($row)::text)), '')) AS fingerprint FROM public.$identifier t"
    }
    $data = Read-Database ('SELECT json_agg(result ORDER BY table_name) FROM (' + ($queries -join ' UNION ALL ') + ') result;')
    $plainData = @($data | ForEach-Object { [ordered]@{ table_name = $_.table_name; row_count = $_.row_count; fingerprint = $_.fingerprint } })
    $evidence = [ordered]@{ capturedUtc = [DateTime]::UtcNow.ToString('o'); phase = $Phase; metadata = $metadata; data = $plainData }
    $evidencePath = Join-Path $PSScriptRoot ('verification-' + $Phase.ToLowerInvariant() + '.json')
    if (Test-Path -LiteralPath $evidencePath) { throw "Evidence file already exists; preserve it and stop: $evidencePath" }
    if ($Phase -eq 'After') {
        $before = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'verification-before.json') | ConvertFrom-Json
        # Windows PowerShell 5.1 serialized the initial JSON array with a value/Count
        # wrapper. Preserve that original evidence and compare its actual rows.
        $beforeData = if ($before.data.PSObject.Properties['value']) { $before.data.value } else { $before.data }
        $differences = Compare-Object @($beforeData) @($data) -Property table_name, row_count, fingerprint -CaseSensitive
        if (@($beforeData).Count -ne @($data).Count -or $differences) {
            $differences | Format-Table
            throw 'Table counts/content fingerprints changed. Stop and investigate; do not repair automatically.'
        }
        $oldColumns = @($metadata.columns | Where-Object { !($_.table_name -eq 'Studios' -and $_.column_name -in @('Latitude', 'Longitude')) })
        $oldConstraints = @($metadata.constraints | Where-Object { !($_.table_name -eq 'Studios' -and $_.name -eq 'CK_Studios_Coordinates') })
        if (($before.metadata.columns | ConvertTo-Json -Depth 20 -Compress) -cne ($oldColumns | ConvertTo-Json -Depth 20 -Compress) -or
            ($before.metadata.constraints | ConvertTo-Json -Depth 20 -Compress) -cne ($oldConstraints | ConvertTo-Json -Depth 20 -Compress)) {
            throw 'Unrelated column/constraint definitions changed; stop for review.'
        }
    }
    $evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    $data | Format-Table table_name, row_count
    Write-Output "$Phase verification passed. Read-only evidence saved to $evidencePath"
    if ($Phase -eq 'After') { Write-Output 'All row fingerprints unchanged; original schema preserved; 13 constraint cases passed; existing coordinates remain null.' }
} finally {
    $env:PGPASSWORD = $previousPassword
    $env:PGCONNECT_TIMEOUT = $previousTimeout
}
