-- Evidence only: no ownership assignment or repair is authorized by this report.
-- Optional names/timestamps are allowlisted; absent fields are reported as NULL.
-- Only explicitly allowed ownership IDs are output; no user profiles are read.
-- Optional relation queries are SQL strings parsed only after an existence check.
-- query_to_xml runs SELECT only; XML results contain the named report columns.
BEGIN READ ONLY;

-- 0. Confirm whether the target Studio is still missing at diagnostic time.
SELECT CASE WHEN pg_catalog.to_regclass('public."Studios"') IS NOT NULL
THEN pg_catalog.query_to_xml($report$
SELECT '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid AS target_studio_id,
       EXISTS (
           SELECT 1 FROM public."Studios"
           WHERE "Id" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
       ) AS target_studio_exists
$report$, true, false, '')::text
ELSE 'SKIPPED: public.Studios does not exist' END AS target_studio_check;

-- 1 and 2. Every affected service, including services with zero package links.
SELECT CASE WHEN pg_catalog.to_regclass('public."StudioServices"') IS NOT NULL
AND pg_catalog.to_regclass('public."PhotographyPackageServices"') IS NOT NULL
THEN pg_catalog.query_to_xml($report$
SELECT s."Id" AS service_id,
       COALESCE(to_jsonb(s)->>'ServiceName', to_jsonb(s)->>'Name',
                to_jsonb(s)->>'Title') AS service_name,
       s."StudioId" AS studio_id,
       to_jsonb(s)->>'CreatedAt' AS created_at,
       to_jsonb(s)->>'UpdatedAt' AS updated_at,
       (SELECT count(*) FROM public."PhotographyPackageServices" ps
        WHERE ps."StudioServiceId" = s."Id") AS package_service_reference_count
FROM public."StudioServices" s
WHERE s."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
ORDER BY s."Id"
$report$, true, false, '')::text
ELSE 'SKIPPED: StudioServices or PhotographyPackageServices does not exist'
END AS services_and_reference_counts;

-- 3. Every package using the missing StudioId, not just Silver Package.
SELECT CASE WHEN pg_catalog.to_regclass('public."PhotographyPackages"') IS NOT NULL
THEN pg_catalog.query_to_xml($report$
SELECT p."Id" AS package_id,
       COALESCE(to_jsonb(p)->>'Name', to_jsonb(p)->>'PackageName',
                to_jsonb(p)->>'Title') AS package_name,
       p."StudioId" AS studio_id,
       to_jsonb(p)->>'CreatedAt' AS created_at,
       to_jsonb(p)->>'UpdatedAt' AS updated_at
FROM public."PhotographyPackages" p
WHERE p."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
ORDER BY p."Id"
$report$, true, false, '')::text
ELSE 'SKIPPED: PhotographyPackages does not exist' END AS affected_packages;

-- 4a. Explicit metadata coverage for the four requested tables.
-- Missing tables/columns must not be mistaken for a zero matching-row count.
SELECT required.table_name,
       EXISTS (
           SELECT 1 FROM pg_catalog.pg_class c
           JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
           JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
           WHERE n.nspname = 'public' AND c.relname = required.table_name
             AND c.relkind IN ('r', 'p') AND a.attname = 'StudioId'
             AND a.attnum > 0 AND NOT a.attisdropped
       ) AS table_has_studio_id
FROM (VALUES ('StudioPortfolios'), ('StudioServices'), ('Bookings'),
             ('StudioAvailabilities'), ('PhotographyPackages')) required(table_name)
ORDER BY required.table_name;

-- 4b. Discover all non-system base/partitioned tables with an exact StudioId
-- column. Count only; never return their records or personal fields.
-- query_to_xml executes ONLY the quoted SELECT count(*) generated below.
-- Inheritance/partition children are counted through their parent, not twice.
-- Permission failures abort the diagnostic rather than silently omit a table.
WITH studio_tables AS (
    SELECT n.nspname AS schema_name, c.relname AS table_name
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
    WHERE c.relkind IN ('r', 'p')
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_'
      AND a.attname = 'StudioId' AND a.attnum > 0 AND NOT a.attisdropped
      AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid = c.oid
      )
)
SELECT t.schema_name, t.table_name,
       ((pg_catalog.xpath('/row/matching_rows/text()',
           pg_catalog.query_to_xml(pg_catalog.format(
               'SELECT count(*) AS matching_rows FROM %I.%I WHERE %I::text = %L',
               t.schema_name, t.table_name, 'StudioId',
               '635a1ffa-c57e-436f-a6f8-a40821582173'
           ), false, true, '')
       ))[1]::text)::bigint AS matching_rows
FROM studio_tables t
ORDER BY t.schema_name, t.table_name;

-- 5a. Full package/service edges touching either affected set.
-- LEFT JOINs also expose missing endpoints. Existing studio endpoints are
-- relational evidence, not a conclusion that the orphan belongs to that studio.
SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM (VALUES ('Studios'), ('PhotographyPackages'),
        ('StudioServices'), ('PhotographyPackageServices')) required(table_name)
    WHERE pg_catalog.to_regclass(pg_catalog.format('public.%I', required.table_name)) IS NULL
)
THEN pg_catalog.query_to_xml($report$
SELECT ps."PhotographyPackageId" AS package_id,
       p."Id" IS NOT NULL AS package_exists,
       p."StudioId" AS package_studio_id,
       owner_p."Id" AS existing_package_studio_id,
       owner_p."StudioName" AS existing_package_studio_name,
       ps."StudioServiceId" AS service_id,
       s."Id" IS NOT NULL AS service_exists,
       s."StudioId" AS service_studio_id,
       owner_s."Id" AS existing_service_studio_id,
       owner_s."StudioName" AS existing_service_studio_name
FROM public."PhotographyPackageServices" ps
LEFT JOIN public."PhotographyPackages" p ON p."Id" = ps."PhotographyPackageId"
LEFT JOIN public."StudioServices" s ON s."Id" = ps."StudioServiceId"
LEFT JOIN public."Studios" owner_p ON owner_p."Id" = p."StudioId"
LEFT JOIN public."Studios" owner_s ON owner_s."Id" = s."StudioId"
WHERE p."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
   OR s."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
ORDER BY ps."PhotographyPackageId", ps."StudioServiceId"
$report$, true, false, '')::text
ELSE 'SKIPPED: one or more package/service evidence tables do not exist'
END AS package_service_edges;

-- 5b. Business evidence through Bookings.PackageId / Bookings.StudioId.
-- Include packages linked to an affected service as well as affected packages.
-- Aggregate only: no booking IDs, customer identifiers, dates, or personal data.
SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM (VALUES ('Studios'), ('PhotographyPackages'), ('StudioServices'),
        ('PhotographyPackageServices'), ('Bookings')) required(table_name)
    WHERE pg_catalog.to_regclass(pg_catalog.format('public.%I', required.table_name)) IS NULL
)
AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = pg_catalog.to_regclass('public."Bookings"')
      AND attname = 'PackageId' AND attnum > 0 AND NOT attisdropped
)
AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = pg_catalog.to_regclass('public."Bookings"')
      AND attname = 'StudioId' AND attnum > 0 AND NOT attisdropped
)
THEN pg_catalog.query_to_xml($report$
WITH chain_packages AS (
    SELECT p."Id" AS package_id
    FROM public."PhotographyPackages" p
    WHERE p."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
    UNION
    SELECT ps."PhotographyPackageId"
    FROM public."PhotographyPackageServices" ps
    JOIN public."StudioServices" s ON s."Id" = ps."StudioServiceId"
    WHERE s."StudioId" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid
)
SELECT cp.package_id,
       b."StudioId" AS booking_studio_id,
       current_studio."Id" AS existing_booking_studio_id,
       current_studio."StudioName" AS existing_booking_studio_name,
       count(b."PackageId") AS booking_reference_count
FROM chain_packages cp
LEFT JOIN public."Bookings" b ON b."PackageId" = cp.package_id
LEFT JOIN public."Studios" current_studio ON current_studio."Id" = b."StudioId"
GROUP BY cp.package_id, b."StudioId", current_studio."Id", current_studio."StudioName"
ORDER BY cp.package_id, b."StudioId"
$report$, true, false, '')::text
ELSE 'SKIPPED: booking evidence requires Studios, PhotographyPackages, StudioServices, PhotographyPackageServices and Bookings with PackageId and StudioId'
END AS booking_evidence;

-- 6. Current studios and their owner IDs. No join to Users or profile fields.
SELECT CASE WHEN pg_catalog.to_regclass('public."Studios"') IS NOT NULL
THEN pg_catalog.query_to_xml($report$
    SELECT s."Id" AS studio_id, s."StudioName" AS studio_name,
           to_jsonb(s)->>'UserId' AS owner_user_id,
           to_jsonb(s)->>'CreatedAt' AS created_at,
           to_jsonb(s)->>'UpdatedAt' AS updated_at
    FROM public."Studios" s ORDER BY s."Id"
$report$, true, false, '')::text
ELSE 'SKIPPED: Studios does not exist' END AS current_studio_ownership;

-- 7. Inspect ownership-ID availability on the four known studio-owned entities.
-- Only UUID/integer ID columns are allowed: a textual CreatedBy could contain
-- an email/name and is deliberately excluded. CreatedByUserId identifies the
-- creator, not necessarily the owner. OwnerId/StudioOwnerId semantics require review.
-- Include records for the missing studio and current studios for comparison.
-- No bookings/customers/reviews or arbitrary personal-data tables are read here.
WITH required(table_name) AS (
    VALUES ('StudioPortfolios'), ('StudioServices'),
           ('StudioAvailabilities'), ('PhotographyPackages')
), metadata AS (
    SELECT r.table_name, c.oid,
           bool_or(a.attname = 'StudioId') AS has_studio_id,
           string_agg(pg_catalog.format('%I', a.attname), ', ' ORDER BY a.attnum)
               FILTER (WHERE a.attname IN ('Id', 'StudioId', 'CreatedAt', 'UpdatedAt')
                   OR (a.attname IN ('UserId', 'OwnerUserId', 'OwnerId',
                                    'StudioOwnerId', 'CreatedByUserId')
                       AND a.atttypid IN ('uuid'::regtype, 'int2'::regtype,
                                         'int4'::regtype, 'int8'::regtype))) AS safe_columns,
           array_agg(a.attname ORDER BY a.attnum) FILTER (
               WHERE a.attname IN ('UserId', 'OwnerUserId', 'OwnerId',
                                  'StudioOwnerId', 'CreatedByUserId')
                 AND a.atttypid IN ('uuid'::regtype, 'int2'::regtype,
                                   'int4'::regtype, 'int8'::regtype)
           ) AS available_ownership_id_columns
    FROM required r
    LEFT JOIN pg_catalog.pg_class c
      ON c.oid = pg_catalog.to_regclass(pg_catalog.format('public.%I', r.table_name))
     AND c.relkind IN ('r', 'p')
    LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    GROUP BY r.table_name, c.oid
)
SELECT m.table_name, m.available_ownership_id_columns,
       CASE WHEN m.oid IS NULL THEN 'SKIPPED: table does not exist'
            WHEN NOT coalesce(m.has_studio_id, false) THEN 'SKIPPED: StudioId column does not exist'
            ELSE pg_catalog.query_to_xml(pg_catalog.format(
                'SELECT %s FROM public.%I WHERE "StudioId"::text = %L %s ORDER BY "StudioId"',
                m.safe_columns, m.table_name,
                '635a1ffa-c57e-436f-a6f8-a40821582173',
                CASE WHEN pg_catalog.to_regclass('public."Studios"') IS NOT NULL
                     THEN 'OR "StudioId" IN (SELECT "Id" FROM public."Studios")'
                     ELSE '' END
            ), true, false, '')::text END AS ownership_and_timestamp_evidence,
       CASE WHEN m.available_ownership_id_columns IS NULL
            THEN 'No allowlisted ownership ID column found; StudioId/timestamps alone cannot identify the missing owner.'
            ELSE 'Compare IDs with current Studios.UserId only where the relational meaning agrees; matching numeric values alone are not proof.'
       END AS ownership_limit
FROM metadata m ORDER BY m.table_name;

-- 8. Existing FK metadata clarifies the target of ownership IDs, if constrained.
-- Attribute names and table names only; no referenced user rows are selected.
SELECT src.relname AS source_table, sa.attname AS source_column,
       tn.nspname AS referenced_schema, tgt.relname AS referenced_table,
       ta.attname AS referenced_column, fk.convalidated AS constraint_validated
FROM pg_catalog.pg_constraint fk
JOIN pg_catalog.pg_class src ON src.oid = fk.conrelid
JOIN pg_catalog.pg_namespace sn ON sn.oid = src.relnamespace
JOIN pg_catalog.pg_class tgt ON tgt.oid = fk.confrelid
JOIN pg_catalog.pg_namespace tn ON tn.oid = tgt.relnamespace
CROSS JOIN LATERAL unnest(fk.conkey, fk.confkey) AS key_pair(source_num, target_num)
JOIN pg_catalog.pg_attribute sa ON sa.attrelid = src.oid AND sa.attnum = key_pair.source_num
JOIN pg_catalog.pg_attribute ta ON ta.attrelid = tgt.oid AND ta.attnum = key_pair.target_num
WHERE fk.contype = 'f' AND sn.nspname = 'public'
  AND src.relname IN ('Studios', 'StudioPortfolios', 'StudioServices',
                      'StudioAvailabilities', 'PhotographyPackages')
  AND sa.attname IN ('StudioId', 'UserId', 'OwnerUserId', 'OwnerId',
                    'StudioOwnerId', 'CreatedByUserId')
ORDER BY source_table, source_column, referenced_table;

SELECT 'Evidence paths: available package/service links, optional booking links, and allowlisted ownership IDs with FK metadata. '
       'A current studio appearing on these paths is evidence for review, not proof of ownership. '
       'No current-studio endpoint means no connection was found through these paths; '
       'it does not prove that no historical connection ever existed. '
       'Matching names, timestamps, or the number of current studios do not establish ownership. '
       'Skipped sections are unavailable evidence, not zero matches. '
       'If no orphan ownership ID survives, the missing Studios.UserId cannot be recovered from StudioId alone. '
       'No user profiles, personal fields or unstructured history/snapshots were inspected for ownership.'
       AS interpretation;

ROLLBACK;
