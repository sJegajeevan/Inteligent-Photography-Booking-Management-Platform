-- Diagnostic evidence only. Service-linked studios are not approved owners.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH orphan_packages AS (
    SELECT p."Id", p."StudioId",
           (SELECT jsonb_object_agg(f.key, f.value)
            FROM jsonb_each(to_jsonb(p)) f
            WHERE f.key IN ('Name', 'PackageName', 'Title', 'CreatedAt', 'UpdatedAt'))
           AS optional_package_fields
    FROM public."PhotographyPackages" p
    WHERE NOT EXISTS (SELECT 1 FROM public."Studios" s WHERE s."Id" = p."StudioId")
), service_studios AS (
    SELECT DISTINCT ps."PhotographyPackageId" AS package_id,
           to_jsonb(ss)->>'StudioId' AS studio_id
    FROM public."PhotographyPackageServices" ps
    JOIN orphan_packages p ON p."Id" = ps."PhotographyPackageId"
    JOIN public."StudioServices" ss ON ss."Id" = ps."StudioServiceId"
    WHERE to_jsonb(ss)->>'StudioId' IS NOT NULL
), evidence AS (
    SELECT p."Id" AS package_id, p."StudioId" AS missing_studio_id,
           coalesce(p.optional_package_fields, '{}'::jsonb) AS optional_package_fields,
           links.related_service_rows > 0 AS has_package_service_rows,
           links.related_service_rows,
           ARRAY(SELECT ss.studio_id FROM service_studios ss
                 WHERE ss.package_id = p."Id" ORDER BY ss.studio_id)
                 AS distinct_service_studio_ids,
           ARRAY(SELECT ss.studio_id FROM service_studios ss
                 WHERE ss.package_id = p."Id"
                   AND EXISTS (SELECT 1 FROM public."Studios" s
                               WHERE s."Id"::text = ss.studio_id)
                 ORDER BY ss.studio_id) AS existing_studio_ids_from_services
    FROM orphan_packages p
    CROSS JOIN LATERAL (
        SELECT count(*) AS related_service_rows
        FROM public."PhotographyPackageServices" ps
        WHERE ps."PhotographyPackageId" = p."Id"
    ) links
)
SELECT jsonb_pretty(jsonb_build_object(
    'studio_services_has_studio_id_column', EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public."StudioServices"'::regclass
          AND attname = 'StudioId' AND attnum > 0 AND NOT attisdropped),
    'orphan_packages', coalesce((
        SELECT jsonb_agg(to_jsonb(e) || jsonb_build_object(
            'single_existing_studio_candidate_from_services',
            cardinality(e.existing_studio_ids_from_services) = 1
        ) ORDER BY e.package_id) FROM evidence e
    ), '[]'::jsonb),
    'existing_studios', coalesce((
        SELECT jsonb_agg(jsonb_build_object('Id', s."Id") || coalesce((
            SELECT jsonb_object_agg(f.key, f.value)
            FROM jsonb_each(to_jsonb(s)) f
            WHERE f.key IN ('StudioName', 'Name')
        ), '{}'::jsonb) ORDER BY s."Id")
        FROM public."Studios" s
    ), '[]'::jsonb),
    'interpretation', 'Service-linked studio IDs are evidence only; no correct owner is selected or approved.'
)) AS orphan_package_studio_diagnostic;

ROLLBACK;
