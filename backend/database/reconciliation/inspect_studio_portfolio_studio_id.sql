-- Inspect only studio-portfolio -> studio FK metadata and aggregate counts.
-- Compare against current-model.json and the EF non-nullable Guid StudioId.
-- Results are evidence only; do not normalize types/nullability or ownership.
-- No reconciliation exceptions are changed by this diagnostic.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH target AS (
    SELECT 'public."StudioPortfolios"'::regclass AS child_oid,
           'public."Studios"'::regclass AS parent_oid
), candidates AS (
    SELECT c.*,
           c.contype = 'f' AND c.confrelid = t.parent_oid
           AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.child_oid AND attname = 'StudioId'
                 AND NOT attisdropped)]::smallint[]
           AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.parent_oid AND attname = 'Id'
                 AND NOT attisdropped)]::smallint[] AS exact_relationship
    FROM pg_constraint c CROSS JOIN target t
    WHERE c.conrelid = t.child_oid
      AND (c.conname = 'FK_StudioPortfolios_Studios_StudioId'
           OR (c.contype = 'f' AND (c.confrelid = t.parent_oid
           OR starts_with(c.conname::text, 'FK_StudioPortfolios_Studios_')
           OR EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid = t.child_oid AND a.attnum = ANY(c.conkey)
                        AND a.attname = 'StudioId'))))
)
SELECT jsonb_pretty(jsonb_build_object(
    'expected', jsonb_build_object(
        'child_column', 'public.StudioPortfolios.StudioId',
        'parent_column', 'public.Studios.Id',
        'column_type', 'uuid', 'both_columns_not_null', true,
        'ef_studio_id_required', true, 'ef_clr_type', 'System.Guid',
        'reconcile_not_null_approved', false, 'reconcile_missing_fk_approved', false,
        'constraint_name', 'FK_StudioPortfolios_Studios_StudioId',
        'match', 'SIMPLE', 'update', 'NO ACTION', 'delete', 'CASCADE',
        'validated', true, 'enforced', true,
        'deferrable', false, 'initially_deferred', false),
    'relationship_fk_exists', EXISTS (
        SELECT 1 FROM candidates WHERE exact_relationship),
    'preflight_compatible_fk_exists', EXISTS (
        SELECT 1 FROM candidates WHERE exact_relationship
          AND convalidated AND NOT condeferrable AND NOT condeferred
          AND coalesce((to_jsonb(candidates)->>'conenforced')::boolean, true)
          AND confdeltype = 'c' AND confupdtype = 'a' AND confmatchtype = 's'),
    'preflight_compatible_fk_exists_under_another_name', EXISTS (
        SELECT 1 FROM candidates WHERE exact_relationship
          AND convalidated AND NOT condeferrable AND NOT condeferred
          AND coalesce((to_jsonb(candidates)->>'conenforced')::boolean, true)
          AND confdeltype = 'c' AND confupdtype = 'a' AND confmatchtype = 's'
          AND conname <> 'FK_StudioPortfolios_Studios_StudioId'),
    'foreign_key_candidates', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'name', c.conname,
            'constraint_type', c.contype,
            'definition', pg_get_constraintdef(c.oid, true),
            'exact_relationship', c.exact_relationship,
            'validated', c.convalidated,
            'enforced', coalesce((to_jsonb(c)->>'conenforced')::boolean, true),
            'deferrable', c.condeferrable,
            'initially_deferred', c.condeferred,
            'delete_code', c.confdeltype,
            'update_code', c.confupdtype,
            'match_code', c.confmatchtype,
            'referenced_key_index', CASE WHEN c.conindid <> 0 THEN pg_get_indexdef(c.conindid) END
        ) ORDER BY c.conname) FROM candidates c
    ), '[]'::jsonb),
    'columns', (
        SELECT jsonb_agg(jsonb_build_object(
            'table', a.attrelid::regclass::text,
            'column', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'type_oid', a.atttypid,
            'type_modifier', a.atttypmod,
            'udt_schema', type_ns.nspname, 'udt_name', data_type.typname,
            'type_kind', data_type.typtype,
            'domain_base_type', CASE WHEN data_type.typbasetype <> 0
                THEN format_type(data_type.typbasetype, data_type.typtypmod) END,
            'not_null', a.attnotnull, 'nullable', NOT a.attnotnull,
            'generated_code', a.attgenerated,
            'generated_state', CASE a.attgenerated WHEN '' THEN 'not generated'
                WHEN 's' THEN 'stored' WHEN 'v' THEN 'virtual' ELSE 'unknown' END,
            'identity_code', a.attidentity,
            'identity_state', CASE a.attidentity WHEN '' THEN 'not identity'
                WHEN 'a' THEN 'always' WHEN 'd' THEN 'by default' ELSE 'unknown' END,
            'default_or_generation_expression', pg_get_expr(default_def.adbin, default_def.adrelid),
            'collation', CASE WHEN a.attcollation <> 0
                THEN format('%I.%I', collation_ns.nspname, collation_def.collname) END,
            'expected_type', 'uuid', 'expected_nullable', false,
            'expected_generated_code', '',
            'preflight_type_mismatch', format_type(a.atttypid, a.atttypmod) <> 'uuid',
            'preflight_nullability_mismatch', a.attnotnull <> true,
            'preflight_generated_mismatch', a.attgenerated <> '',
            'failed_preflight_comparisons', array_remove(ARRAY[
                CASE WHEN format_type(a.atttypid, a.atttypmod) <> 'uuid'
                    THEN 'format_type(atttypid, atttypmod) <> uuid' END,
                CASE WHEN a.attnotnull <> true THEN 'attnotnull <> true' END,
                CASE WHEN a.attgenerated <> '' THEN 'attgenerated <> empty string' END
            ], NULL),
            'preflight_column_conflict', format_type(a.atttypid, a.atttypmod) <> 'uuid'
                OR a.attnotnull <> true OR a.attgenerated <> ''

        ) ORDER BY a.attrelid, a.attnum)
        FROM target t CROSS JOIN pg_attribute a
        JOIN pg_type data_type ON data_type.oid = a.atttypid
        JOIN pg_namespace type_ns ON type_ns.oid = data_type.typnamespace
        LEFT JOIN pg_attrdef default_def ON default_def.adrelid = a.attrelid AND default_def.adnum = a.attnum
        LEFT JOIN pg_collation collation_def ON collation_def.oid = a.attcollation
        LEFT JOIN pg_namespace collation_ns ON collation_ns.oid = collation_def.collnamespace
        WHERE a.attnum > 0 AND NOT a.attisdropped
          AND ((a.attrelid = t.child_oid AND a.attname = 'StudioId')
            OR (a.attrelid = t.parent_oid AND a.attname = 'Id'))
    ),
    'studios_id_keys', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'name', c.conname,
            'definition', pg_get_constraintdef(c.oid, true),
            'validated', c.convalidated,
            'deferrable', c.condeferrable,
            'initially_deferred', c.condeferred,
            'exact_single_column_id_key', c.conkey = ARRAY[(
                SELECT attnum FROM pg_attribute
                WHERE attrelid = t.parent_oid AND attname = 'Id'
                  AND attnum > 0 AND NOT attisdropped)]::smallint[]
        ) ORDER BY c.conname)
        FROM pg_constraint c CROSS JOIN target t
        WHERE c.conrelid = t.parent_oid AND c.contype IN ('p', 'u')
          AND EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid = t.parent_oid AND a.attnum = ANY(c.conkey)
                        AND a.attname = 'Id')
    ), '[]'::jsonb),
    'relevant_indexes', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'table', idx.indrelid::regclass::text,
            'name', index_tbl.relname,
            'definition', pg_get_indexdef(idx.indexrelid),
            'primary', idx.indisprimary, 'unique', idx.indisunique,
            'valid', idx.indisvalid, 'ready', idx.indisready,
            'live', idx.indislive, 'immediate', idx.indimmediate,
            'access_method', access_method.amname,
            'key_attribute_count', idx.indnkeyatts,
            'total_attribute_count', idx.indnatts,
            'partial', idx.indpred IS NOT NULL,
            'expression_based', idx.indexprs IS NOT NULL,
            'exact_target_key_column', idx.indnkeyatts = 1
                AND idx.indkey[0] = attr.attnum,
            'eligible_parent_unique_index', idx.indrelid = t.parent_oid
                AND idx.indisunique AND idx.indisvalid AND idx.indisready
                AND idx.indislive AND idx.indimmediate
                AND idx.indpred IS NULL AND idx.indexprs IS NULL
                AND idx.indnkeyatts = 1 AND idx.indkey[0] = attr.attnum
        ) ORDER BY idx.indrelid, index_tbl.relname)
        FROM target t
        JOIN pg_attribute attr
          ON ((attr.attrelid = t.child_oid AND attr.attname = 'StudioId')
           OR (attr.attrelid = t.parent_oid AND attr.attname = 'Id'))
         AND attr.attnum > 0 AND NOT attr.attisdropped
        JOIN pg_index idx ON idx.indrelid = attr.attrelid
        JOIN pg_class index_tbl ON index_tbl.oid = idx.indexrelid
        JOIN pg_am access_method ON access_method.oid = index_tbl.relam
        WHERE attr.attnum = ANY(idx.indkey)
           OR (idx.indrelid = t.child_oid
               AND index_tbl.relname = 'IX_StudioPortfolios_StudioId')
    ), '[]'::jsonb),
    'index_interpretation', 'The referenced Id requires an eligible unique/primary key. A child StudioId index is not required to create the FK, but the current reconciliation separately requires the non-unique (StudioId) model index to exist and be compatible.',
    'preflight_comparison', 'format_type(atttypid, atttypmod) <> expected type OR attnotnull <> NOT expected nullable OR attgenerated <> empty string. Expected uuid, nullable=false, not generated. The approved StudioAvailabilities nullability exception does not apply to StudioPortfolios. Identity, default and collation are reported but are not compared by this conflict check.',
    'row_comparison_method', 'Studio IDs are compared as text to keep inspection valid even if the child has an incompatible type. For uuid columns this preserves equality. If types differ, unmatched text values require review; this report does not normalize or cast child values to uuid.',
    'distinct_studio_ids', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('studio_id', grouped.studio_id,
            'row_count', grouped.row_count) ORDER BY grouped.studio_id)
        FROM (SELECT portfolio."StudioId"::text AS studio_id, count(*) AS row_count
              FROM public."StudioPortfolios" portfolio
              GROUP BY portfolio."StudioId"::text) grouped
    ), '[]'::jsonb),
    'row_counts', (
        SELECT jsonb_build_object(
            'total_studio_portfolio_rows', count(*),
            'distinct_non_null_studio_id_count', count(DISTINCT ps."StudioId"::text),
            'null_studio_id_rows', count(*) FILTER (WHERE ps."StudioId" IS NULL),
            'orphan_studio_rows', count(*) FILTER (
                WHERE ps."StudioId" IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM public."Studios" s
                                  WHERE s."Id"::text = ps."StudioId"::text)),
            'zero_orphan_and_null_violations', count(*) FILTER (
                WHERE ps."StudioId" IS NULL OR NOT EXISTS (
                    SELECT 1 FROM public."Studios" s WHERE s."Id"::text = ps."StudioId"::text)) = 0)
        FROM public."StudioPortfolios" ps
    )
)) AS studio_portfolio_studio_id_inspection;

ROLLBACK;
