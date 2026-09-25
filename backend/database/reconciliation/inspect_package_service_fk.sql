-- Catalog-only inspection of PhotographyPackageServices -> PhotographyPackages.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '30s';

WITH target AS (
    SELECT
        to_regclass('public."PhotographyPackageServices"') AS child_oid,
        to_regclass('public."PhotographyPackages"') AS parent_oid
),
fk AS (
    SELECT c.*
    FROM pg_catalog.pg_constraint c
    CROSS JOIN target t
    WHERE c.contype = 'f'
      AND c.conrelid = t.child_oid
      AND (
          c.confrelid = t.parent_oid
          OR EXISTS (
              SELECT 1
              FROM pg_catalog.pg_attribute a
              WHERE a.attrelid = c.conrelid
                AND a.attnum = ANY(c.conkey)
                AND a.attname = 'PhotographyPackageId'
          )
          OR c.conname::text LIKE
             'FK_PhotographyPackageServices_PhotographyPackages_%'
      )
),
relevant_columns AS (
    SELECT a.attrelid, a.attnum
    FROM pg_catalog.pg_attribute a
    CROSS JOIN target t
    WHERE a.attnum > 0 AND NOT a.attisdropped
      AND (
          (a.attrelid = t.child_oid
           AND a.attname IN ('PhotographyPackageId', 'StudioServiceId'))
          OR (a.attrelid = t.parent_oid AND a.attname = 'Id')
      )
    UNION
    SELECT f.conrelid, k.attnum
    FROM fk f CROSS JOIN LATERAL unnest(f.conkey) k(attnum)
    UNION
    SELECT f.confrelid, k.attnum
    FROM fk f CROSS JOIN LATERAL unnest(f.confkey) k(attnum)
),
relevant_tables AS (
    SELECT child_oid AS oid FROM target
    UNION SELECT parent_oid FROM target
    UNION SELECT confrelid FROM fk
)
SELECT pg_catalog.jsonb_pretty(
    pg_catalog.jsonb_build_object(
        'foreign_keys', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'name', f.conname,
                'table', format('%I.%I', ns.nspname, tbl.relname),
                'referenced_table', format('%I.%I', pns.nspname, pt.relname),
                'definition', pg_get_constraintdef(f.oid, true),
                'delete_code', f.confdeltype,
                'update_code', f.confupdtype,
                'match_code', f.confmatchtype,
                'validated', f.convalidated,
                'deferrable', f.condeferrable,
                'initially_deferred', f.condeferred,
                'supporting_index', pg_get_indexdef(f.conindid),
                'supporting_index_valid', ix.indisvalid,
                'supporting_index_unique', ix.indisunique,
                'supporting_index_primary', ix.indisprimary
            ) ORDER BY f.conname)
            FROM fk f
            JOIN pg_class tbl ON tbl.oid = f.conrelid
            JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
            JOIN pg_class pt ON pt.oid = f.confrelid
            JOIN pg_namespace pns ON pns.oid = pt.relnamespace
            LEFT JOIN pg_index ix ON ix.indexrelid = f.conindid
        ), '[]'::jsonb),
        'columns', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'table', format('%I.%I', ns.nspname, tbl.relname),
                'column', a.attname,
                'type', format_type(a.atttypid, a.atttypmod),
                'not_null', a.attnotnull
            ) ORDER BY ns.nspname, tbl.relname, a.attnum)
            FROM relevant_columns r
            JOIN pg_attribute a
              ON a.attrelid = r.attrelid AND a.attnum = r.attnum
            JOIN pg_class tbl ON tbl.oid = a.attrelid
            JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
        ), '[]'::jsonb),
        'primary_unique_keys', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'table', format('%I.%I', ns.nspname, tbl.relname),
                'name', c.conname,
                'definition', pg_get_constraintdef(c.oid, true),
                'validated', c.convalidated,
                'deferrable', c.condeferrable,
                'initially_deferred', c.condeferred
            ) ORDER BY ns.nspname, tbl.relname, c.conname)
            FROM pg_constraint c
            JOIN pg_class tbl ON tbl.oid = c.conrelid
            JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
            WHERE c.contype IN ('p', 'u')
              AND c.conrelid IN (SELECT oid FROM relevant_tables)
        ), '[]'::jsonb)
    )
) AS specific_fk_inspection;

ROLLBACK;
