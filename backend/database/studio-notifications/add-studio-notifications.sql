-- Apply this additive change before deploying the updated API.
-- Existing rows remain customer notifications (StudioId is NULL).
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE "Notifications" ADD COLUMN "StudioId" uuid NULL;
ALTER TABLE "Notifications" ADD CONSTRAINT "FK_Notifications_Studios_StudioId"
    FOREIGN KEY ("StudioId") REFERENCES "Studios" ("Id") ON DELETE CASCADE;
CREATE INDEX "IX_Notifications_StudioId_CreatedAt" ON "Notifications" ("StudioId", "CreatedAt");
CREATE INDEX "IX_Notifications_StudioId_IsRead" ON "Notifications" ("StudioId", "IsRead");
COMMIT;
