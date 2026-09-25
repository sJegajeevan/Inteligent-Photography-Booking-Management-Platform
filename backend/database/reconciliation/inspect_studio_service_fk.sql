-- Inspect only package-service -> studio-service FK metadata and aggregate counts.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH target AS (
    SELECT 'public."PhotographyPackageServices"'::regclass AS child_oid,
           'public."StudioServices"'::regclass AS parent_oid
), candidates AS (
    SELECT c.*,
           c.confrelid = t.parent_oid
           AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.child_oid AND attname = 'StudioServiceId'
                 AND NOT attisdropped)]::smallint[]
           AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.parent_oid AND attname = 'Id'
                 AND NOT attisdropped)]::smallint[] AS exact_relationship
    FROM pg_constraint c CROSS JOIN target t
    WHERE c.conrelid = t.child_oid AND c.contype = 'f'
      AND (c.confrelid = t.parent_oid
           OR c.conname = 'FK_PhotographyPackageServices_StudioServices_StudioServiceId'
           OR EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid = t.child_oid AND a.attnum = ANY(c.conkey)
                        AND a.attname = 'StudioServiceId'))
)
SELECT jsonb_pretty(jsonb_build_object(
    'relationship_fk_exists', EXISTS (
        SELECT 1 FROM candidates WHERE exact_relationship),
    'preflight_compatible_fk_exists', EXISTS (
        SELECT 1 FROM candidates WHERE exact_relationship
          AND convalidated AND NOT condeferrable
          AND confdeltype = 'c' AND confupdtype = 'a' AND confmatchtype = 's'),
    'foreign_key_candidates', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'name', c.conname,
            'definition', pg_get_constraintdef(c.oid, true),
            'exact_relationship', c.exact_relationship,
            'validated', c.convalidated,
            'deferrable', c.condeferrable,
            'initially_deferred', c.condeferred,
            'delete_code', c.confdeltype,
            'update_code', c.confupdtype,
            'match_code', c.confmatchtype,
            'referenced_key_index', pg_get_indexdef(c.conindid)
        ) ORDER BY c.conname) FROM candidates c
    ), '[]'::jsonb),
    'columns', (
        SELECT jsonb_agg(jsonb_build_object(
            'table', a.attrelid::regclass::text,
            'column', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'not_null', a.attnotnull
        ) ORDER BY a.attrelid, a.attnum)
        FROM pg_attribute a CROSS JOIN target t
        WHERE a.attnum > 0 AND NOT a.attisdropped
          AND ((a.attrelid = t.child_oid AND a.attname = 'StudioServiceId')
            OR (a.attrelid = t.parent_oid AND a.attname = 'Id'))
    ),
    'studio_services_id_keys', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'name', c.conname,
            'definition', pg_get_constraintdef(c.oid, true),
            'validated', c.convalidated,
            'deferrable', c.condeferrable
        ) ORDER BY c.conname)
        FROM pg_constraint c CROSS JOIN target t
        WHERE c.conrelid = t.parent_oid AND c.contype IN ('p', 'u')
          AND EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid = t.parent_oid AND a.attnum = ANY(c.conkey)
                        AND a.attname = 'Id')
    ), '[]'::jsonb),
    'row_counts', (
        SELECT jsonb_build_object(
            'total_package_service_rows', count(*),
            'orphan_studio_service_rows', count(*) FILTER (
                WHERE NOT EXISTS (SELECT 1 FROM public."StudioServices" s
                                  WHERE s."Id" = ps."StudioServiceId")))
        FROM public."PhotographyPackageServices" ps
    )
)) AS studio_service_fk_inspection;

ROLLBACK;
