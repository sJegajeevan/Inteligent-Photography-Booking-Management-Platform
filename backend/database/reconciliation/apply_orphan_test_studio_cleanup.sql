-- ONE-TIME APPLY: cleanup of explicitly confirmed disposable TEST DATA only.
-- Derived from cleanup_orphan_test_studio.sql after its successful rollback dry run.
-- REQUIRES the operator-verified, recoverable backup BEFORE execution:
-- database/reconciliation/photography_booking_before_cleanup.backup
-- The operator reports this backup verified; SQL does not verify the backup file.
-- This file COMMITs only after all guards and post-deletion checks succeed.
-- Expected counts are fixed to the successful dry run; drift requires review.
-- Run in a quiet maintenance window with no concurrent schema changes.
-- Any error aborts the transaction; ON_ERROR_STOP disconnect rolls it back.
-- This is intentionally not rerunnable after successful cleanup.
-- Run with psql -X -v ON_ERROR_STOP=1. Never execute fragments separately.
-- No reconciliation/migrations are invoked. No durable schema changes are made.
BEGIN;
SET LOCAL search_path = pg_catalog;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL row_security = off;

DO $cleanup$
DECLARE
    orphan_id constant uuid := '635a1ffa-c57e-436f-a6f8-a40821582173';
    protected_id constant uuid := 'fa245b2d-5fa0-4255-91ee-783b21a9911f';
    r record;
    f record;
    ownership_attr record;
    ids uuid[];
    package_ids uuid[] := ARRAY[]::uuid[];
    service_ids uuid[] := ARRAY[]::uuid[];
    portfolio_ids uuid[] := ARRAY[]::uuid[];
    all_ids uuid[] := ARRAY[orphan_id];
    scopes jsonb := '{}'::jsonb;
    before_counts jsonb := '{}'::jsonb;
    expected_counts constant jsonb := '{
        "PackageAddons": 2,
        "PhotographyPackages": 1,
        "PhotographyPackageServices": 1,
        "StudioAvailabilities": 3,
        "StudioPortfolioImages": 7,
        "StudioPortfolios": 4,
        "StudioServices": 3
    }'::jsonb;
    verification jsonb := '[]'::jsonb;
    n bigint;
    deleted_count bigint;
    predicate text;
    join_predicate text;
    source_name text;
    destination_name text;
    allowed_relationship boolean;
    protected_before jsonb;
    protected_after jsonb;
BEGIN
    -- Serialize this cleanup and freeze all existing application tables while
    -- checking references, including unconstrained UUID/ID columns. These locks
    -- block concurrent writers; normal reads remain possible. Use a quiet window.
    PERFORM pg_catalog.pg_advisory_xact_lock(63521582173::bigint);
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
        WHERE ns.nspname !~ '^pg_' AND ns.nspname <> 'information_schema'
          AND c.relkind IN ('f', 'p')
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_inherits i
        JOIN pg_catalog.pg_class c ON c.oid = i.inhrelid
        JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
        WHERE ns.nspname !~ '^pg_' AND ns.nspname <> 'information_schema'
    ) THEN
        RAISE EXCEPTION 'STOP: foreign, partitioned or inherited application tables require separate review';
    END IF;

    FOR r IN
        SELECT ns.nspname, c.relname FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
        WHERE ns.nspname !~ '^pg_' AND ns.nspname <> 'information_schema'
          AND c.relkind = 'r' ORDER BY ns.nspname, c.relname
    LOOP
        EXECUTE format('LOCK TABLE %I.%I IN SHARE ROW EXCLUSIVE MODE', r.nspname, r.relname);
    END LOOP;

    IF to_regclass('public."Studios"') IS NULL THEN
        RAISE EXCEPTION 'STOP: Studios is absent; cannot verify ownership';
    END IF;
    IF EXISTS (SELECT 1 FROM public."Studios" WHERE "Id" = orphan_id) THEN
        RAISE EXCEPTION 'STOP: target Studio now exists';
    END IF;
    SELECT to_jsonb(s) INTO protected_before FROM public."Studios" s WHERE s."Id" = protected_id;
    IF protected_before IS NULL THEN
        RAISE EXCEPTION 'STOP: expected protected current Studio is absent';
    END IF;
    -- The protected row is compared in memory only; never print its contents.

    -- Confirm exact operator-reported parent counts. A missing parent table is
    -- contradictory evidence: abort clearly instead of issuing a missing-table query.
    FOR r IN SELECT * FROM (VALUES
        ('PhotographyPackages', 1), ('StudioServices', 3),
        ('StudioAvailabilities', 3), ('StudioPortfolios', 4)
    ) expected(table_name, expected_count)
    LOOP
        IF to_regclass(format('public.%I', r.table_name)) IS NULL THEN
            RAISE EXCEPTION 'STOP: confirmed parent table % is absent', r.table_name;
        END IF;
        SELECT count(*) INTO n FROM pg_catalog.pg_attribute
        WHERE attrelid = to_regclass(format('public.%I', r.table_name))
          AND attname IN ('Id', 'StudioId') AND atttypid = 'uuid'::regtype
          AND attnum > 0 AND NOT attisdropped;
        IF n <> 2 THEN
            RAISE EXCEPTION 'STOP: unexpected Id/StudioId schema on %', r.table_name;
        END IF;
        EXECUTE format('SELECT array_agg("Id" ORDER BY "Id"), count(*) FROM public.%I WHERE "StudioId" = $1', r.table_name)
            INTO ids, n USING orphan_id;
        IF n <> r.expected_count OR array_position(ids, NULL) IS NOT NULL THEN
            RAISE EXCEPTION 'STOP: % expected % target rows, found % (IDs must be non-null)', r.table_name, r.expected_count, n;
        END IF;
        all_ids := all_ids || ids;
        scopes := scopes || jsonb_build_object(r.table_name,
            format('t."Id" = ANY(%L::uuid[]) AND t."StudioId" = %L::uuid', ids, orphan_id));
        CASE r.table_name
            WHEN 'PhotographyPackages' THEN package_ids := ids;
            WHEN 'StudioServices' THEN service_ids := ids;
            WHEN 'StudioPortfolios' THEN portfolio_ids := ids;
            ELSE NULL;
        END CASE;
        RAISE NOTICE 'Pre-cleanup %.%: % target rows', 'public', r.table_name, n;
    END LOOP;

    -- Optional dependents: absent tables are skipped; malformed tables abort.
    FOR r IN SELECT * FROM (VALUES
        ('PhotographyPackageServices', ARRAY['PhotographyPackageId', 'StudioServiceId']::text[]),
        ('StudioPortfolioImages', ARRAY['Id', 'StudioPortfolioId']::text[]),
        ('PackageAddons', ARRAY['Id', 'PackageId']::text[])
    ) optional(table_name, required_columns)
    LOOP
        IF to_regclass(format('public.%I', r.table_name)) IS NULL THEN
            RAISE NOTICE 'SKIPPED: optional table public.% is absent', r.table_name;
            verification := verification || jsonb_build_array(jsonb_build_object(
                'table_name', r.table_name, 'status', 'SKIPPED: absent optional table',
                'planned_deletions', NULL, 'remaining_target_rows', NULL));
            CONTINUE;
        END IF;
        SELECT count(*) INTO n FROM pg_catalog.pg_attribute
        WHERE attrelid = to_regclass(format('public.%I', r.table_name))
          AND attname = ANY(r.required_columns) AND atttypid = 'uuid'::regtype
          AND attnum > 0 AND NOT attisdropped;
        IF n <> cardinality(r.required_columns) THEN
            RAISE EXCEPTION 'STOP: unexpected dependent schema on %', r.table_name;
        END IF;
        IF r.table_name = 'PhotographyPackageServices' THEN
            predicate := format('(t."PhotographyPackageId" = ANY(%L::uuid[]) OR t."StudioServiceId" = ANY(%L::uuid[]))', package_ids, service_ids);
            EXECUTE format('SELECT count(*) FROM public.%I t WHERE %s AND (t."PhotographyPackageId" = ANY(%L::uuid[]) AND t."StudioServiceId" = ANY(%L::uuid[])) IS NOT TRUE',
                r.table_name, predicate, package_ids, service_ids) INTO n;
            IF n <> 0 THEN
                RAISE EXCEPTION 'STOP: % package/service links cross outside the confirmed orphan set', n;
            END IF;
        ELSIF r.table_name = 'PackageAddons' THEN
            -- Derive add-ons only through the already-verified orphan package IDs.
            predicate := format('t."PackageId" = ANY(%L::uuid[])', package_ids);
            EXECUTE format('SELECT coalesce(array_agg(t."Id" ORDER BY t."Id"), ARRAY[]::uuid[]), count(*) FROM public.%I t WHERE %s',
                r.table_name, predicate) INTO ids, n;
            IF array_position(ids, NULL) IS NOT NULL THEN
                RAISE EXCEPTION 'STOP: package add-on has null Id';
            END IF;
            RAISE NOTICE 'Pre-cleanup public.PackageAddons: % dependent rows; IDs: %', n, ids;
            -- Recheck every captured ID against an actual target package and its
            -- orphan StudioId. This also detects a duplicate ID on another package.
            EXECUTE format('SELECT count(*) FROM public.%I t WHERE t."Id" = ANY($1) AND NOT EXISTS (SELECT 1 FROM public."PhotographyPackages" p WHERE p."Id" = t."PackageId" AND p."Id" = ANY($2) AND p."StudioId" = $3)',
                r.table_name) INTO n USING ids, package_ids, orphan_id;
            IF n <> 0 THEN
                RAISE EXCEPTION 'STOP: selected package add-on IDs include rows outside the target orphan packages';
            END IF;
            all_ids := all_ids || ids;
            -- Captured IDs and target package membership are both required to delete.
            predicate := format('t."Id" = ANY(%L::uuid[]) AND t."PackageId" = ANY(%L::uuid[])', ids, package_ids);
        ELSE
            predicate := format('t."StudioPortfolioId" = ANY(%L::uuid[])', portfolio_ids);
            EXECUTE format('SELECT coalesce(array_agg(t."Id"), ARRAY[]::uuid[]) FROM public.%I t WHERE %s', r.table_name, predicate) INTO ids;
            IF array_position(ids, NULL) IS NOT NULL THEN
                RAISE EXCEPTION 'STOP: portfolio image has null Id';
            END IF;
            all_ids := all_ids || ids;
        END IF;
        scopes := scopes || jsonb_build_object(r.table_name, predicate);
    END LOOP;

    -- Reject side effects/hidden rows and unexpected ownership before any DELETE.
    FOR r IN SELECT key AS table_name, value AS filter FROM jsonb_each_text(scopes)
    LOOP
        IF EXISTS (SELECT 1 FROM pg_catalog.pg_class
                   WHERE oid = to_regclass(format('public.%I', r.table_name))
                     AND (relkind <> 'r' OR relpersistence <> 'p' OR relrowsecurity))
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                      WHERE tgrelid = to_regclass(format('public.%I', r.table_name))
                        AND NOT tgisinternal AND tgenabled <> 'D')
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_rewrite
                      WHERE ev_class = to_regclass(format('public.%I', r.table_name))) THEN
            RAISE EXCEPTION 'STOP: unexpected table kind, RLS, trigger or rule on %', r.table_name;
        END IF;
        FOR ownership_attr IN SELECT attname FROM pg_catalog.pg_attribute
            WHERE attrelid = to_regclass(format('public.%I', r.table_name))
              AND attnum > 0 AND NOT attisdropped
              AND attname IN ('StudioId', 'UserId', 'OwnerId', 'OwnerUserId', 'StudioOwnerId', 'CreatedByUserId')
        LOOP
            IF ownership_attr.attname = 'StudioId' THEN
                EXECUTE format('SELECT count(*) FROM public.%I t WHERE (%s) AND t.%I::text IS DISTINCT FROM %L',
                    r.table_name, r.filter, ownership_attr.attname, orphan_id::text) INTO n;
            ELSE
                EXECUTE format('SELECT count(*) FROM public.%I t WHERE (%s) AND t.%I IS NOT NULL',
                    r.table_name, r.filter, ownership_attr.attname) INTO n;
            END IF;
            IF n <> 0 THEN
                RAISE EXCEPTION 'STOP: % target rows in % have unexpected ownership field %; review privately', n, r.table_name, ownership_attr.attname;
            END IF;
        END LOOP;
        EXECUTE format('SELECT count(*) FROM public.%I t WHERE %s', r.table_name, r.filter) INTO n;
        before_counts := before_counts || jsonb_build_object(r.table_name, n);
        RAISE NOTICE 'Planned deletion public.%: % rows', r.table_name, n;
    END LOOP;

    -- Reject unreviewed outgoing relationships carried by target rows, including
    -- owner references under unexpected column names. Known StudioId references
    -- and the four explicit dependent relationships are the only allowed FKs.
    FOR f IN
        SELECT fk.*, child.relname AS child_table, pn.nspname AS parent_schema,
               parent.relname AS parent_table
        FROM pg_catalog.pg_constraint fk
        JOIN pg_catalog.pg_class child ON child.oid = fk.conrelid
        JOIN pg_catalog.pg_namespace cn ON cn.oid = child.relnamespace
        JOIN pg_catalog.pg_class parent ON parent.oid = fk.confrelid
        JOIN pg_catalog.pg_namespace pn ON pn.oid = parent.relnamespace
        WHERE fk.contype = 'f' AND cn.nspname = 'public' AND scopes ? child.relname
    LOOP
        SELECT string_agg(format('t.%I IS NOT NULL', ca.attname), ' OR ' ORDER BY k.ord),
               min(ca.attname::text), min(pa.attname::text)
        INTO predicate, source_name, destination_name
        FROM unnest(f.conkey, f.confkey) WITH ORDINALITY k(child_num, parent_num, ord)
        JOIN pg_catalog.pg_attribute ca ON ca.attrelid = f.conrelid AND ca.attnum = k.child_num
        JOIN pg_catalog.pg_attribute pa ON pa.attrelid = f.confrelid AND pa.attnum = k.parent_num;
        allowed_relationship := f.parent_schema = 'public' AND cardinality(f.conkey) = 1
            AND destination_name = 'Id' AND (
                (f.child_table IN ('PhotographyPackages', 'StudioServices', 'StudioAvailabilities', 'StudioPortfolios')
                    AND f.parent_table = 'Studios' AND source_name = 'StudioId') OR
                (f.child_table = 'PhotographyPackageServices' AND f.parent_table = 'PhotographyPackages' AND source_name = 'PhotographyPackageId') OR
                (f.child_table = 'PhotographyPackageServices' AND f.parent_table = 'StudioServices' AND source_name = 'StudioServiceId') OR
                (f.child_table = 'PackageAddons' AND f.parent_table = 'PhotographyPackages' AND source_name = 'PackageId') OR
                (f.child_table = 'StudioPortfolioImages' AND f.parent_table = 'StudioPortfolios' AND source_name = 'StudioPortfolioId'));
        IF NOT allowed_relationship THEN
            EXECUTE format('SELECT count(*) FROM public.%I t WHERE (%s) AND (%s)',
                f.child_table, scopes->>f.child_table, predicate) INTO n;
            IF n > 0 THEN
                RAISE EXCEPTION 'STOP: target rows have unreviewed outgoing FK from % to %.%', f.child_table, f.parent_schema, f.parent_table;
            END IF;
        END IF;
    END LOOP;

    -- Inspect every declared incoming FK, including composite keys and other
    -- schemas. CASCADE/SET NULL actions are not permission to touch other rows.
    FOR f IN
        SELECT fk.*, ns.nspname AS child_schema, child.relname AS child_table,
               parent.relname AS parent_table
        FROM pg_catalog.pg_constraint fk
        JOIN pg_catalog.pg_class child ON child.oid = fk.conrelid
        JOIN pg_catalog.pg_namespace ns ON ns.oid = child.relnamespace
        JOIN pg_catalog.pg_class parent ON parent.oid = fk.confrelid
        JOIN pg_catalog.pg_namespace pn ON pn.oid = parent.relnamespace
        WHERE fk.contype = 'f' AND pn.nspname = 'public' AND scopes ? parent.relname
    LOOP
        SELECT string_agg(format('c.%I = t.%I', ca.attname, pa.attname), ' AND ' ORDER BY k.ord),
               min(ca.attname::text), min(pa.attname::text)
        INTO join_predicate, source_name, destination_name
        FROM unnest(f.conkey, f.confkey) WITH ORDINALITY k(child_num, parent_num, ord)
        JOIN pg_catalog.pg_attribute ca ON ca.attrelid = f.conrelid AND ca.attnum = k.child_num
        JOIN pg_catalog.pg_attribute pa ON pa.attrelid = f.confrelid AND pa.attnum = k.parent_num;
        EXECUTE format('SELECT count(*) FROM %I.%I c JOIN public.%I t ON %s WHERE %s',
            f.child_schema, f.child_table, f.parent_table, join_predicate, scopes->>f.parent_table) INTO n;
        RAISE NOTICE 'FK dependency %.% -> public.%: % referencing rows', f.child_schema, f.child_table, f.parent_table, n;
        allowed_relationship := f.child_schema = 'public' AND cardinality(f.conkey) = 1
            AND destination_name = 'Id' AND (
                (f.child_table = 'PhotographyPackageServices' AND f.parent_table = 'PhotographyPackages' AND source_name = 'PhotographyPackageId') OR
                (f.child_table = 'PhotographyPackageServices' AND f.parent_table = 'StudioServices' AND source_name = 'StudioServiceId') OR
                (f.child_table = 'PackageAddons' AND f.parent_table = 'PhotographyPackages' AND source_name = 'PackageId') OR
                (f.child_table = 'StudioPortfolioImages' AND f.parent_table = 'StudioPortfolios' AND source_name = 'StudioPortfolioId'));
        IF n > 0 AND NOT allowed_relationship THEN
            RAISE EXCEPTION 'STOP: unexpected FK references from %.% to %', f.child_schema, f.child_table, f.parent_table;
        END IF;
    END LOOP;

    -- Also detect unconstrained references (e.g. Bookings.PackageId or an external
    -- PackageAddonId), without assuming those tables exist. Scan all
    -- UUID columns and text ID-suffixed columns. Only counts/metadata are printed.
    -- Arbitrary IDs embedded in JSON/free text are outside this relational check.
    FOR r IN
        SELECT ns.nspname, tbl.relname, tbl.relrowsecurity, attr.attname
        FROM pg_catalog.pg_class tbl
        JOIN pg_catalog.pg_namespace ns ON ns.oid = tbl.relnamespace
        JOIN pg_catalog.pg_attribute attr ON attr.attrelid = tbl.oid
        WHERE tbl.relkind = 'r' AND ns.nspname !~ '^pg_' AND ns.nspname <> 'information_schema'
          AND attr.attnum > 0 AND NOT attr.attisdropped
          AND (attr.atttypid = 'uuid'::regtype OR
              (attr.attname ~* 'id$' AND attr.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)))
        ORDER BY ns.nspname, tbl.relname, attr.attname
    LOOP
        IF r.relrowsecurity THEN
            RAISE EXCEPTION 'STOP: RLS could hide references in %.%', r.nspname, r.relname;
        END IF;
        predicate := CASE WHEN r.nspname = 'public' AND scopes ? r.relname
                          THEN format('AND (%s) IS NOT TRUE', scopes->>r.relname) ELSE '' END;
        EXECUTE format('SELECT count(*) FROM %I.%I t WHERE t.%I::text = ANY($1) %s',
            r.nspname, r.relname, r.attname, predicate) INTO n USING all_ids::text[];
        RAISE NOTICE 'Outside-scope reference check %.%.%: % rows', r.nspname, r.relname, r.attname, n;
        IF n > 0 THEN
            RAISE EXCEPTION 'STOP: unexpected references outside cleanup scope in %.%.%', r.nspname, r.relname, r.attname;
        END IF;
    END LOOP;

    -- Freeze the successful dry-run counts for ALL seven tables, before DELETE.
    -- Optional-table discovery remains safe, but a now-missing confirmed table
    -- produces a missing key and therefore aborts rather than weakening scope.
    IF before_counts IS DISTINCT FROM expected_counts THEN
        RAISE EXCEPTION 'STOP: reviewed counts changed; expected %, found %',
            expected_counts, before_counts;
    END IF;

    -- All guards completed. Explicit dependents first; never rely on cascades.
    FOR r IN SELECT * FROM (VALUES
        (1, 'PhotographyPackageServices'), (2, 'StudioPortfolioImages'),
        (3, 'PackageAddons'), (4, 'PhotographyPackages'), (5, 'StudioServices'),
        (6, 'StudioAvailabilities'), (7, 'StudioPortfolios')
    ) deletion_order(position, table_name) ORDER BY position
    LOOP
        IF NOT (scopes ? r.table_name) THEN CONTINUE; END IF;
        EXECUTE format('DELETE FROM public.%I t WHERE %s', r.table_name, scopes->>r.table_name);
        GET DIAGNOSTICS deleted_count = ROW_COUNT;
        IF deleted_count <> (before_counts->>r.table_name)::bigint THEN
            RAISE EXCEPTION 'STOP: deleted count mismatch for %', r.table_name;
        END IF;
        RAISE NOTICE 'Deleted within pending transaction public.%: % rows', r.table_name, deleted_count;
    END LOOP;

    -- Verify with the ORIGINAL captured IDs, including deleted parents' children.
    FOR r IN SELECT key AS table_name, value AS filter FROM jsonb_each_text(scopes)
    LOOP
        EXECUTE format('SELECT count(*) FROM public.%I t WHERE %s', r.table_name, r.filter) INTO n;
        RAISE NOTICE 'Post-cleanup public.% remaining original target rows: %', r.table_name, n;
        IF n <> 0 THEN RAISE EXCEPTION 'STOP: target rows remain in %', r.table_name; END IF;
        verification := verification || jsonb_build_array(jsonb_build_object(
            'table_name', r.table_name, 'status', 'verified before commit',
            'planned_deletions', (before_counts->>r.table_name)::bigint,
            'remaining_target_rows', n));
    END LOOP;
    SELECT to_jsonb(s) INTO protected_after FROM public."Studios" s WHERE s."Id" = protected_id;
    IF protected_after IS NULL OR protected_after IS DISTINCT FROM protected_before THEN
        RAISE EXCEPTION 'STOP: protected current Studio changed';
    END IF;
    IF EXISTS (SELECT 1 FROM public."Studios" WHERE "Id" = orphan_id) THEN
        RAISE EXCEPTION 'STOP: missing Studio unexpectedly exists';
    END IF;
    -- Transaction-local report only, not a table or durable database record.
    PERFORM set_config('snapsync_cleanup.verification', verification::text, true);
END;
$cleanup$;

-- Force any deferred constraint failures before the final report and COMMIT.
SET CONSTRAINTS ALL IMMEDIATE;

-- Post-cleanup SELECTs show the verified transaction state BEFORE COMMIT.
-- Original dependent IDs were separately verified above (not rederived
-- from deleted parents). No customer/user records or private fields are output.
SELECT '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid AS target_studio_id,
       EXISTS (SELECT 1 FROM public."Studios" WHERE "Id" = '635a1ffa-c57e-436f-a6f8-a40821582173'::uuid) AS target_studio_exists,
       EXISTS (SELECT 1 FROM public."Studios" WHERE "Id" = 'fa245b2d-5fa0-4255-91ee-783b21a9911f'::uuid) AS protected_studio_exists;

SELECT table_name, status, planned_deletions, remaining_target_rows
FROM pg_catalog.jsonb_to_recordset(
    pg_catalog.current_setting('snapsync_cleanup.verification')::jsonb
) AS checked(table_name text, status text, planned_deletions bigint, remaining_target_rows bigint)
ORDER BY table_name;

SELECT 'All cleanup guards and verification succeeded; committing only the confirmed orphan test data cleanup.' AS result;
COMMIT;
