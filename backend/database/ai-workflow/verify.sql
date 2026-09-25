-- READ ONLY. Run only after the separately approved deployment; not executed during preparation.
BEGIN TRANSACTION READ ONLY;
SELECT table_name, column_name, data_type, is_nullable, character_maximum_length
FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('AiWorkflows','AiWorkflowEvents','AiWorkflowApprovals')
ORDER BY table_name, ordinal_position;
SELECT c.relname AS table_name, p.conname, p.convalidated, pg_get_constraintdef(p.oid) AS definition
FROM pg_constraint p JOIN pg_class c ON c.oid=p.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('AiWorkflows','AiWorkflowEvents','AiWorkflowApprovals')
ORDER BY c.relname, p.conname;
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename IN ('AiWorkflows','AiWorkflowEvents','AiWorkflowApprovals')
ORDER BY tablename, indexname;
ROLLBACK;
