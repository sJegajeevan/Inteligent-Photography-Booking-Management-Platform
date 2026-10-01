-- PREPARATION ONLY. No automatic execution. Explicit database deployment approval required.
-- Additive replacement of ONE constraint; no tables, rows, or migration history changed.
-- Keep the historical ai-workflow deployment SQL unchanged.
-- Offline checks do not execute PostgreSQL: validate in an authorized disposable DB before deployment.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
LOCK TABLE public."AiWorkflowEvents" IN ACCESS EXCLUSIVE MODE;
DO $review$
DECLARE
    target regclass := 'public."AiWorkflowEvents"'::regclass;
    legacy_expr text := $legacy$"DetailsJson" IS NULL OR (jsonb_typeof("DetailsJson") = 'object' AND ("DetailsJson" - ARRAY['proposalVersion','errorCode','attempt']::text[]) = '{}'::jsonb)$legacy$;
    new_expr text := $journey$
CASE WHEN "EventType" = 'JourneyV1' THEN COALESCE((
    jsonb_typeof("DetailsJson") = 'object'
    AND ("DetailsJson" - 'journey') = '{}'::jsonb
    AND jsonb_typeof("DetailsJson"->'journey') = 'object'
    AND octet_length("DetailsJson"::text) <= 4096
    AND (NOT (("DetailsJson"->'journey') ? 'v') OR (jsonb_typeof(("DetailsJson"->'journey')->'v') = 'number' AND (("DetailsJson"->'journey')->>'v') ~ '^1$'))
    AND (NOT (("DetailsJson"->'journey') ? 'revision') OR (jsonb_typeof(("DetailsJson"->'journey')->'revision') = 'number' AND (("DetailsJson"->'journey')->>'revision') ~ '^[1-9][0-9]{0,8}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'sequence') OR (jsonb_typeof(("DetailsJson"->'journey')->'sequence') = 'number' AND (("DetailsJson"->'journey')->>'sequence') ~ '^[1-9][0-9]{0,8}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'operationId') OR (jsonb_typeof(("DetailsJson"->'journey')->'operationId') = 'string' AND (("DetailsJson"->'journey')->>'operationId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'studioId') OR (jsonb_typeof(("DetailsJson"->'journey')->'studioId') = 'string' AND (("DetailsJson"->'journey')->>'studioId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'packageId') OR (jsonb_typeof(("DetailsJson"->'journey')->'packageId') = 'string' AND (("DetailsJson"->'journey')->>'packageId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'sourceEventId') OR (jsonb_typeof(("DetailsJson"->'journey')->'sourceEventId') = 'string' AND (("DetailsJson"->'journey')->>'sourceEventId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'optionEventId') OR (jsonb_typeof(("DetailsJson"->'journey')->'optionEventId') = 'string' AND (("DetailsJson"->'journey')->>'optionEventId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'rank') OR (jsonb_typeof(("DetailsJson"->'journey')->'rank') = 'number' AND (("DetailsJson"->'journey')->>'rank') ~ '^[1-5]$'))
    AND (NOT (("DetailsJson"->'journey') ? 'extraHours') OR (jsonb_typeof(("DetailsJson"->'journey')->'extraHours') = 'number' AND (("DetailsJson"->'journey')->>'extraHours') ~ '^(0|[1-9][0-9]{0,2}|1000)$'))
    AND (NOT (("DetailsJson"->'journey') ? 'quotedPrice') OR (jsonb_typeof(("DetailsJson"->'journey')->'quotedPrice') = 'string' AND (("DetailsJson"->'journey')->>'quotedPrice') ~ '^(0|[1-9][0-9]{0,15})([.][0-9]{1,2})?$'))
    AND (NOT (("DetailsJson"->'journey') ? 'durationHours') OR (jsonb_typeof(("DetailsJson"->'journey')->'durationHours') = 'string' AND (("DetailsJson"->'journey')->>'durationHours') ~ '^((0|[1-9]|1[0-9]|2[0-3])([.][0-9]{1,12})?|24([.]0{1,12})?)$'))
    AND (NOT (("DetailsJson"->'journey') ? 'date') OR (jsonb_typeof(("DetailsJson"->'journey')->'date') = 'string' AND (("DetailsJson"->'journey')->>'date') ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'))
    AND (NOT (("DetailsJson"->'journey') ? 'startTime') OR (jsonb_typeof(("DetailsJson"->'journey')->'startTime') = 'string' AND (("DetailsJson"->'journey')->>'startTime') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,7})?$'))
    AND (NOT (("DetailsJson"->'journey') ? 'endTime') OR (jsonb_typeof(("DetailsJson"->'journey')->'endTime') = 'string' AND (("DetailsJson"->'journey')->>'endTime') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,7})?$'))
    AND (NOT (("DetailsJson"->'journey') ? 'expiresAt') OR (jsonb_typeof(("DetailsJson"->'journey')->'expiresAt') = 'string' AND (("DetailsJson"->'journey')->>'expiresAt') ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]{1,7})?Z$'))
    AND (NOT (("DetailsJson"->'journey') ? 'errorCode') OR (jsonb_typeof(("DetailsJson"->'journey')->'errorCode') = 'string' AND (("DetailsJson"->'journey')->>'errorCode') ~ '^[a-z][a-z0-9_]{0,63}$'))
    AND (NOT (("DetailsJson"->'journey') ? 'invalidatesFrom') OR (jsonb_typeof(("DetailsJson"->'journey')->'invalidatesFrom') = 'string' AND (("DetailsJson"->'journey')->>'invalidatesFrom') ~ '^(StudioMatching|PackageRecommendation|Scheduling|Validation)$'))
    AND (NOT (("DetailsJson"->'journey') ? 'operationId') OR (("DetailsJson"->'journey')->>'operationId') <> '00000000-0000-0000-0000-000000000000')
    AND (NOT (("DetailsJson"->'journey') ? 'studioId') OR (("DetailsJson"->'journey')->>'studioId') <> '00000000-0000-0000-0000-000000000000')
    AND (NOT (("DetailsJson"->'journey') ? 'packageId') OR (("DetailsJson"->'journey')->>'packageId') <> '00000000-0000-0000-0000-000000000000')
    AND (NOT (("DetailsJson"->'journey') ? 'sourceEventId') OR (("DetailsJson"->'journey')->>'sourceEventId') <> '00000000-0000-0000-0000-000000000000')
    AND (NOT (("DetailsJson"->'journey') ? 'optionEventId') OR (("DetailsJson"->'journey')->>'optionEventId') <> '00000000-0000-0000-0000-000000000000')
    AND (NOT (("DetailsJson"->'journey') ? 'reason') OR (jsonb_typeof(("DetailsJson"->'journey')->'reason') = 'string' AND char_length(("DetailsJson"->'journey')->>'reason') BETWEEN 1 AND 300))
    AND (NOT (("DetailsJson"->'journey') ? 'optionEventIds') OR (jsonb_typeof(("DetailsJson"->'journey')->'optionEventIds') = 'array' AND (("DetailsJson"->'journey')->'optionEventIds')::text ~ '^\["[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"(,[[:space:]]*"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"){0,4}\]$' AND position('00000000-0000-0000-0000-000000000000' in (("DetailsJson"->'journey')->'optionEventIds')::text) = 0))
    AND (
        (("DetailsJson"->'journey')->>'kind' = 'started' AND "StepName" = ANY (ARRAY['StudioMatching','PackageRecommendation','Scheduling','Validation']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','sourceEventId']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'studio-option' AND "StepName" = ANY (ARRAY['StudioMatching']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','studioId','rank']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','studioId','rank','reason']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'package-option' AND "StepName" = ANY (ARRAY['PackageRecommendation']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','sourceEventId','studioId','packageId','rank','extraHours','quotedPrice','durationHours']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','sourceEventId','studioId','packageId','rank','extraHours','quotedPrice','durationHours','reason']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'schedule-option' AND "StepName" = ANY (ARRAY['Scheduling']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','sourceEventId','studioId','packageId','rank','date','startTime','endTime']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','sourceEventId','studioId','packageId','rank','date','startTime','endTime','reason']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'completed' AND "StepName" = ANY (ARRAY['StudioMatching','PackageRecommendation','Scheduling']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','optionEventIds']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','optionEventIds']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'selected' AND "StepName" = ANY (ARRAY['StudioMatching','PackageRecommendation','Scheduling']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','sourceEventId','optionEventId','invalidatesFrom']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','sourceEventId','optionEventId','invalidatesFrom']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'validated' AND "StepName" = ANY (ARRAY['Validation']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','sourceEventId','quotedPrice','expiresAt']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','sourceEventId','quotedPrice','expiresAt']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'failed' AND "StepName" = ANY (ARRAY['StudioMatching','PackageRecommendation','Scheduling','Validation']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','errorCode']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','errorCode','sourceEventId']::text[]) = '{}'::jsonb)
        OR (("DetailsJson"->'journey')->>'kind' = 'rewound' AND "StepName" = ANY (ARRAY['StudioMatching','PackageRecommendation','Scheduling','Validation']::text[]) AND ("DetailsJson"->'journey') ?& ARRAY['v','revision','sequence','operationId','kind','invalidatesFrom']::text[] AND (("DetailsJson"->'journey') - ARRAY['v','revision','sequence','operationId','kind','invalidatesFrom']::text[]) = '{}'::jsonb)
    )
    AND ((("DetailsJson"->'journey')->>'kind' = 'failed' AND NOT "Success")
        OR (("DetailsJson"->'journey')->>'kind' <> 'failed' AND "Success"))
    AND (("DetailsJson"->'journey')->>'kind' <> 'selected'
        OR ("DetailsJson"->'journey')->>'invalidatesFrom' = CASE "StepName"
            WHEN 'StudioMatching' THEN 'PackageRecommendation'
            WHEN 'PackageRecommendation' THEN 'Scheduling'
            WHEN 'Scheduling' THEN 'Validation' END)
    AND (("DetailsJson"->'journey')->>'kind' <> 'rewound'
        OR ("DetailsJson"->'journey')->>'invalidatesFrom' = "StepName")
), FALSE) ELSE ("DetailsJson" IS NULL OR (jsonb_typeof("DetailsJson") = 'object' AND ("DetailsJson" - ARRAY['proposalVersion','errorCode','attempt']::text[]) = '{}'::jsonb)) END
$journey$;
    current_expr text;
    expected_legacy text;
    expected_new text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = target AND relkind = 'r')
       OR EXISTS (SELECT 1 FROM pg_inherits WHERE inhrelid = target OR inhparent = target) THEN
        RAISE EXCEPTION 'Expected a non-inherited ordinary table';
    END IF;
    SELECT pg_get_expr(conbin, conrelid, false) INTO current_expr
    FROM pg_constraint WHERE conrelid = target
      AND conname = 'CK_AiWorkflowEvents_Details' AND contype = 'c'
      AND convalidated AND conislocal AND coninhcount = 0;
    IF current_expr IS NULL THEN
        RAISE EXCEPTION 'Expected validated local details constraint';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = target AND conname IN (
        'CK_AiWorkflowEvents_Details_review_legacy', 'CK_AiWorkflowEvents_Details_review_v2')) THEN
        RAISE EXCEPTION 'Reserved review constraint name already exists';
    END IF;
    EXECUTE format('ALTER TABLE public."AiWorkflowEvents" ADD CONSTRAINT
        "CK_AiWorkflowEvents_Details_review_legacy" CHECK (%s) NOT VALID', legacy_expr);
    EXECUTE format('ALTER TABLE public."AiWorkflowEvents" ADD CONSTRAINT
        "CK_AiWorkflowEvents_Details_review_v2" CHECK (%s) NOT VALID', new_expr);
    SELECT pg_get_expr(conbin, conrelid, false) INTO expected_legacy
    FROM pg_constraint WHERE conrelid = target AND conname = 'CK_AiWorkflowEvents_Details_review_legacy';
    SELECT pg_get_expr(conbin, conrelid, false) INTO expected_new
    FROM pg_constraint WHERE conrelid = target AND conname = 'CK_AiWorkflowEvents_Details_review_v2';
    IF current_expr = expected_legacy THEN
        IF EXISTS (SELECT 1 FROM public."AiWorkflowEvents" WHERE "EventType" = 'JourneyV1') THEN
            RAISE EXCEPTION 'JourneyV1 already in use; review existing rows';
        END IF;
        ALTER TABLE public."AiWorkflowEvents" VALIDATE CONSTRAINT "CK_AiWorkflowEvents_Details_review_v2";
        ALTER TABLE public."AiWorkflowEvents" DROP CONSTRAINT "CK_AiWorkflowEvents_Details";
        ALTER TABLE public."AiWorkflowEvents" RENAME CONSTRAINT "CK_AiWorkflowEvents_Details_review_v2" TO "CK_AiWorkflowEvents_Details";
    ELSIF current_expr = expected_new THEN
        ALTER TABLE public."AiWorkflowEvents" DROP CONSTRAINT "CK_AiWorkflowEvents_Details_review_v2";
    ELSE
        RAISE EXCEPTION 'Unexpected details constraint definition; no change';
    END IF;
    ALTER TABLE public."AiWorkflowEvents" DROP CONSTRAINT "CK_AiWorkflowEvents_Details_review_legacy";
END;
$review$;
COMMIT;
