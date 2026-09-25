-- Inspect only studio -> user ownership FK metadata and aggregate counts.
-- Compare against current-model.json and the EF non-nullable Int32 UserId.
-- Results are evidence only; do not normalize types/nullability or ownership.
-- No reconciliation exceptions are changed by this diagnostic.
-- Ownership IDs/counts only: no user profiles, contacts, credentials or tokens.
-- Never infer an owner or approve a repair from this report alone.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH target AS (
    SELECT 'public."Studios"'::regclass AS child_oid,
           'public."Users"'::regclass AS parent_oid
), candidates AS (
    SELECT c.*,
           c.contype = 'f' AND c.confrelid = t.parent_oid
           AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.child_oid AND attname = 'UserId'
                 AND NOT attisdropped)]::smallint[]
           AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute
               WHERE attrelid = t.parent_oid AND attname = 'Id'
                 AND NOT attisdropped)]::smallint[] AS exact_relationship
    FROM pg_constraint c CROSS JOIN target t
    WHERE c.conrelid = t.child_oid
      AND (c.conname = 'FK_Studios_Users_UserId'
           OR (c.contype = 'f' AND (c.confrelid = t.parent_oid
           OR starts_with(c.conname::text, 'FK_Studios_Users_')
           OR EXISTS (SELECT 1 FROM pg_attribute a
                      WHERE a.attrelid = t.child_oid AND a.attnum = ANY(c.conkey)
                        AND a.attname = 'UserId'))))
)
SELECT jsonb_pretty(jsonb_build_object(
    'expected', jsonb_build_object(
        'child_column', 'public.Studios.UserId',
        'parent_column', 'public.Users.Id',
        'column_type', 'integer', 'both_columns_not_null', true,
        'ef_user_id_required', true, 'ef_clr_type', 'System.Int32',
        'reconcile_not_null_approved', false, 'reconcile_missing_fk_approved', false,
        'ef_user_id_unique', true, 'expected_unique_index', 'IX_Studios_UserId',
        'unique_index_creation_approved', false,
        'constraint_name', 'FK_Studios_Users_UserId',
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
          AND conname <> 'FK_Studios_Users_UserId'),
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
            'expected_type', 'integer', 'expected_nullable', false,
            'expected_generated_code', '',
            'preflight_type_mismatch', format_type(a.atttypid, a.atttypmod) <> 'integer',
            'preflight_nullability_mismatch', a.attnotnull <> true,
            'preflight_generated_mismatch', a.attgenerated <> '',
            'failed_preflight_comparisons', array_remove(ARRAY[
                CASE WHEN format_type(a.atttypid, a.atttypmod) <> 'integer'
                    THEN 'format_type(atttypid, atttypmod) <> integer' END,
                CASE WHEN a.attnotnull <> true THEN 'attnotnull <> true' END,
                CASE WHEN a.attgenerated <> '' THEN 'attgenerated <> empty string' END
            ], NULL),
            'preflight_column_conflict', format_type(a.atttypid, a.atttypmod) <> 'integer'
                OR a.attnotnull <> true OR a.attgenerated <> ''

        ) ORDER BY a.attrelid, a.attnum)
        FROM target t CROSS JOIN pg_attribute a
        JOIN pg_type data_type ON data_type.oid = a.atttypid
        JOIN pg_namespace type_ns ON type_ns.oid = data_type.typnamespace
        LEFT JOIN pg_attrdef default_def ON default_def.adrelid = a.attrelid AND default_def.adnum = a.attnum
        LEFT JOIN pg_collation collation_def ON collation_def.oid = a.attcollation
        LEFT JOIN pg_namespace collation_ns ON collation_ns.oid = collation_def.collnamespace
        WHERE a.attnum > 0 AND NOT a.attisdropped
          AND ((a.attrelid = t.child_oid AND a.attname = 'UserId')
            OR (a.attrelid = t.parent_oid AND a.attname = 'Id'))
    ),
    'users_id_keys', COALESCE((
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
          ON ((attr.attrelid = t.child_oid AND attr.attname = 'UserId')
           OR (attr.attrelid = t.parent_oid AND attr.attname = 'Id'))
         AND attr.attnum > 0 AND NOT attr.attisdropped
        JOIN pg_index idx ON idx.indrelid = attr.attrelid
        JOIN pg_class index_tbl ON index_tbl.oid = idx.indexrelid
        JOIN pg_am access_method ON access_method.oid = index_tbl.relam
        WHERE attr.attnum = ANY(idx.indkey)
           OR EXISTS (SELECT 1 FROM pg_depend dependency
               WHERE dependency.classid = 'pg_class'::regclass
                 AND dependency.objid = idx.indexrelid
                 AND dependency.refclassid = 'pg_class'::regclass
                 AND dependency.refobjid = attr.attrelid
                 AND dependency.refobjsubid = attr.attnum)
           OR (idx.indrelid = t.child_oid
               AND index_tbl.relname = 'IX_Studios_UserId')
    ), '[]'::jsonb),
    'index_interpretation', 'The referenced Id requires an eligible unique/primary key. A child UserId index is not required to create the FK, but the current reconciliation separately requires the unique (UserId) model index to exist and be compatible.',
    'preflight_comparison', 'format_type(atttypid, atttypmod) <> expected type OR attnotnull <> NOT expected nullable OR attgenerated <> empty string. Expected integer, nullable=false, not generated. No approved nullability exception applies to Studios.UserId. Identity, default and collation are reported but are not compared by this conflict check.',
    'row_comparison_method', 'User IDs are compared as text to keep inspection valid even if the child has an incompatible type. For integer columns this preserves equality. If types differ, unmatched text values require review; this report does not normalize or cast child values to integer.',
    'distinct_user_ids', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('user_id', grouped.user_id,
            'row_count', grouped.row_count) ORDER BY grouped.user_id)
        FROM (SELECT service_row."UserId"::text AS user_id, count(*) AS row_count
              FROM public."Studios" service_row
              WHERE service_row."UserId" IS NOT NULL
              GROUP BY service_row."UserId"::text) grouped
    ), '[]'::jsonb),
    'row_counts', (
        SELECT jsonb_build_object(
            'total_studios_rows', count(*),
            'distinct_non_null_user_id_count', count(DISTINCT ps."UserId"::text),
            'null_user_id_rows', count(*) FILTER (WHERE ps."UserId" IS NULL),
            'orphan_user_rows', count(*) FILTER (
                WHERE ps."UserId" IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM public."Users" s
                                  WHERE s."Id"::text = ps."UserId"::text)),
            'zero_orphan_and_null_violations', count(*) FILTER (
                WHERE ps."UserId" IS NULL OR NOT EXISTS (
                    SELECT 1 FROM public."Users" s WHERE s."Id"::text = ps."UserId"::text)) = 0)
        FROM public."Studios" ps
    )
)) AS studios_user_id_inspection;

-- Ownership uniqueness: include named-object collisions, exact key semantics,
-- valid/ready state and attached PK/unique constraints. No user records returned.
WITH user_column AS (
    SELECT attnum FROM pg_attribute
    WHERE attrelid = 'public."Studios"'::regclass AND attname = 'UserId'
      AND attnum > 0 AND NOT attisdropped
), index_candidates AS (
    SELECT index_tbl.oid, index_tbl.relname, idx.indrelid, idx.indisvalid,
           idx.indisready, idx.indislive, idx.indisunique, idx.indimmediate,
           coalesce(idx.indrelid = 'public."Studios"'::regclass
               AND idx.indisunique AND idx.indisvalid AND idx.indisready
               AND idx.indislive AND idx.indimmediate AND method.amname = 'btree'
               AND idx.indexprs IS NULL AND idx.indpred IS NULL
               AND idx.indnkeyatts = 1 AND idx.indkey[0] = col.attnum
               AND NOT EXISTS (SELECT 1 FROM unnest(idx.indoption) option WHERE option <> 0),
               false) AS compatible_unique_user_id
    FROM pg_class index_tbl
    JOIN pg_namespace ns ON ns.oid = index_tbl.relnamespace
    LEFT JOIN pg_index idx ON idx.indexrelid = index_tbl.oid
    LEFT JOIN pg_am method ON method.oid = index_tbl.relam
    CROSS JOIN user_column col
    WHERE (ns.nspname = 'public' AND index_tbl.relname = 'IX_Studios_UserId')
       OR (idx.indrelid = 'public."Studios"'::regclass
           AND (col.attnum = ANY(idx.indkey) OR EXISTS (
               SELECT 1 FROM pg_depend dependency
               WHERE dependency.classid = 'pg_class'::regclass
                 AND dependency.objid = idx.indexrelid
                 AND dependency.refclassid = 'pg_class'::regclass
                 AND dependency.refobjid = idx.indrelid AND dependency.refobjsubid = col.attnum)))
), duplicate_groups AS (
    SELECT "UserId" AS user_id, count(*) AS studio_count
    FROM public."Studios" WHERE "UserId" IS NOT NULL
    GROUP BY "UserId" HAVING count(*) > 1
)
SELECT jsonb_pretty(jsonb_build_object(
    'expected_unique_index_name', 'IX_Studios_UserId',
    'ef_expects_unique_user_id', true,
    'expected_named_object_exists', EXISTS (
        SELECT 1 FROM index_candidates WHERE relname = 'IX_Studios_UserId'),
    'expected_named_index_compatible_valid_ready', EXISTS (
        SELECT 1 FROM index_candidates WHERE relname = 'IX_Studios_UserId' AND compatible_unique_user_id),
    'equivalent_compatible_unique_index_exists', EXISTS (
        SELECT 1 FROM index_candidates WHERE compatible_unique_user_id),
    'equivalent_compatible_unique_index_under_another_name', EXISTS (
        SELECT 1 FROM index_candidates WHERE compatible_unique_user_id AND relname <> 'IX_Studios_UserId'),
    'index_candidates', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
            'name', candidate.relname,
            'table', candidate.indrelid::regclass::text,
            'definition', CASE WHEN candidate.indrelid IS NOT NULL THEN pg_get_indexdef(candidate.oid) END,
            'unique', candidate.indisunique, 'valid', candidate.indisvalid,
            'ready', candidate.indisready, 'live', candidate.indislive,
            'immediate', candidate.indimmediate,
            'compatible_unique_user_id', candidate.compatible_unique_user_id,
            'attached_key_constraints', coalesce((
                SELECT jsonb_agg(jsonb_build_object(
                    'name', key_constraint.conname,
                    'definition', pg_get_constraintdef(key_constraint.oid, true),
                    'validated', key_constraint.convalidated,
                    'deferrable', key_constraint.condeferrable,
                    'initially_deferred', key_constraint.condeferred))
                FROM pg_constraint key_constraint
                WHERE key_constraint.conindid = candidate.oid
                  AND key_constraint.conrelid = 'public."Studios"'::regclass
                  AND key_constraint.contype IN ('p', 'u')
            ), '[]'::jsonb)
        ) ORDER BY candidate.relname) FROM index_candidates candidate
    ), '[]'::jsonb),
    'duplicate_non_null_user_ids_exist', EXISTS (SELECT 1 FROM duplicate_groups),
    'duplicate_group_count', (SELECT count(*) FROM duplicate_groups),
    'duplicate_user_id_groups', coalesce((
        SELECT jsonb_agg(jsonb_build_object('user_id', user_id, 'studio_count', studio_count)
            ORDER BY user_id) FROM duplicate_groups
    ), '[]'::jsonb),
    'interpretation', 'Evidence only. No NOT NULL, FK, index, backfill, owner reassignment or deletion is approved.'
)) AS studios_ownership_uniqueness;

ROLLBACK;
