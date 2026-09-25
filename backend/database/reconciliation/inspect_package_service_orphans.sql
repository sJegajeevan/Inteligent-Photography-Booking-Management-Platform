-- Return counts only; inspect package-service references without changing data.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

SELECT
    count(*) AS total_package_service_rows,
    count(*) FILTER (
        WHERE NOT EXISTS (
            SELECT 1
            FROM public."PhotographyPackages" AS p
            WHERE p."Id" = ps."PhotographyPackageId"
        )
    ) AS orphan_package_service_rows
FROM public."PhotographyPackageServices" AS ps;

ROLLBACK;
