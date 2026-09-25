-- Catalog metadata and row count only; never creates or changes indexes.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH indexes AS (
    SELECT ic.relname::text AS name,
           pg_get_indexdef(i.indexrelid) AS definition,
           am.amname AS access_method,
           i.indisunique AS is_unique,
           i.indisvalid AS is_valid,
           i.indisready AS is_ready,
           ARRAY(
               SELECT pg_get_indexdef(i.indexrelid, k.pos::integer, true)
               FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
               WHERE k.pos <= i.indnkeyatts ORDER BY k.pos
           ) AS key_columns_or_expressions,
           ARRAY(
               SELECT a.attname::text
               FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
               JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num
               WHERE k.pos > i.indnkeyatts ORDER BY k.pos
           ) AS include_columns,
           i.indisvalid AND i.indisready AND am.amname = 'btree'
           AND NOT i.indisunique AND i.indexprs IS NULL AND i.indpred IS NULL
           AND i.indnkeyatts = 1
           AND NOT EXISTS (SELECT 1 FROM unnest(i.indoption) opt WHERE opt <> 0)
           AND ARRAY(
               SELECT a.attname::text
               FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
               JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num
               WHERE k.pos <= i.indnkeyatts ORDER BY k.pos
           ) = ARRAY['StudioServiceId']::text[] AS matches_preflight
    FROM pg_index i
    JOIN pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_am am ON am.oid = ic.relam
    WHERE i.indrelid = 'public."PhotographyPackageServices"'::regclass
)
SELECT jsonb_pretty(jsonb_build_object(
    'indexes', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name)
                         FROM indexes x), '[]'::jsonb),
    'expected_index_exists_under_another_name', EXISTS (
        SELECT 1 FROM indexes WHERE matches_preflight
          AND name <> 'IX_PhotographyPackageServices_StudioServiceId'),
    'total_package_service_rows', (SELECT count(*)
                                   FROM public."PhotographyPackageServices")
)) AS package_service_index_inspection;

ROLLBACK;
