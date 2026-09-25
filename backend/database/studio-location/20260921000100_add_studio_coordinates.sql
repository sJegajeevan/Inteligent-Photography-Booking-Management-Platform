-- PREPARED ONLY. Requires separate review and authorization before execution.
-- Generated offline from 20260921000100_AddStudioCoordinates.cs.
-- No backfill, defaults, row updates or migration-history changes.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'Studios' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Expected an existing ordinary public.Studios table; stop for review';
  END IF;
END;
$preflight$;
LOCK TABLE public."Studios" IN ACCESS EXCLUSIVE MODE;
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'public."Studios"'::regclass AND NOT attisdropped
      AND attname IN ('Latitude', 'Longitude')
  ) OR EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public."Studios"'::regclass AND conname = 'CK_Studios_Coordinates'
  ) THEN
    RAISE EXCEPTION 'Coordinate columns or constraint already exist; stop for review';
  END IF;
END;
$preflight$;
ALTER TABLE public."Studios" ADD "Latitude" numeric(9,6);

ALTER TABLE public."Studios" ADD "Longitude" numeric(9,6);

ALTER TABLE public."Studios" ADD CONSTRAINT "CK_Studios_Coordinates" CHECK (("Latitude" IS NULL AND "Longitude" IS NULL) OR ("Latitude" IS NOT NULL AND "Longitude" IS NOT NULL AND "Latitude" BETWEEN -90 AND 90 AND "Longitude" BETWEEN -180 AND 180));
COMMIT;
