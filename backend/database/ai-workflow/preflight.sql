-- READ ONLY. Review the target database before authorizing deployment. No customer data is selected.
BEGIN TRANSACTION READ ONLY;
SELECT current_database() AS database_name, current_schema() AS schema_name;
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('Users','Studios','PhotographyPackages')
  AND column_name IN ('Id','UserId','StudioId','Role')
ORDER BY table_name, ordinal_position;
SELECT c.relname AS table_name, p.conname, pg_get_constraintdef(p.oid) AS definition
FROM pg_constraint p JOIN pg_class c ON c.oid=p.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('Users','Studios','PhotographyPackages') AND p.contype='p';
SELECT name, to_regclass(format('public.%I', name)) AS existing_object
FROM (VALUES ('AiWorkflows'), ('AiWorkflowEvents'), ('AiWorkflowApprovals')) AS proposed(name);
ROLLBACK;
