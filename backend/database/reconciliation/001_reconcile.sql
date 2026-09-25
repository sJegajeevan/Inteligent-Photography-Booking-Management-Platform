-- Generated offline from ApplicationDbContext. REVIEW BEFORE EXECUTION.
-- Requires PostgreSQL public schema and the exact documented starting state.
-- Legacy migrations/history are never executed or modified.
BEGIN;
SET LOCAL search_path = pg_catalog, public;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
-- Run in a maintenance window. Freeze the existing tables before validating.
SELECT pg_advisory_xact_lock(20260918, 1);
LOCK TABLE public."Users" IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public."PackageAddons" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."PhotographyPackageServices" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."PhotographyPackages" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."StudioAvailabilities" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."StudioPortfolioImages" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."StudioPortfolios" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."StudioServices" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."Studios" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."__EFMigrationsHistory" IN SHARE MODE;
DO $target_locks$ DECLARE target_name text; BEGIN
FOREACH target_name IN ARRAY ARRAY['BookingLocations','BookingStatusHistories','Bookings','Notifications','Reviews'] LOOP
IF to_regclass(format('public.%I', target_name)) IS NOT NULL THEN
EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE', target_name);
END IF; END LOOP; END; $target_locks$;
-- Fail closed. Targets must be absent or exactly match the reconciled model. Only the explicitly approved
-- missing package/service, package/studio, availability/studio portfolio/studio and service-owner FKs, the service
-- index and exactly StudioAvailabilities.StudioId StudioPortfolios.StudioId and StudioServices.StudioId SET NOT NULL are reconcilable.
-- Studios.UserId also permits guarded integer NOT NULL, FK and known partial-index replacement.
-- Never backfill, repair ownership, delete data or replace incompatible structures.
DO $reconciliation$
DECLARE
    expected_model jsonb := $model${
  "schema": "public",
  "preservedHistory": "202609020001_AddPortfolioImages",
  "tables": [
    {
      "name": "BookingLocations",
      "create": true,
      "columns": [
        {
          "name": "Id",
          "type": "integer",
          "nullable": false,
          "identity": "d",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BookingId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Address",
          "type": "character varying(500)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "City",
          "type": "character varying(100)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Latitude",
          "type": "numeric(9,6)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Longitude",
          "type": "numeric(9,6)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Notes",
          "type": "character varying(1000)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_BookingLocations",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_BookingLocations_Bookings_BookingId",
          "columns": [
            "BookingId"
          ],
          "principalTable": "Bookings",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_BookingLocations_BookingId",
          "columns": [
            "BookingId"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "BookingStatusHistories",
      "create": true,
      "columns": [
        {
          "name": "Id",
          "type": "integer",
          "nullable": false,
          "identity": "d",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BookingId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "OldStatus",
          "type": "integer",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "NewStatus",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ChangedBy",
          "type": "character varying(200)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Reason",
          "type": "character varying(1000)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_BookingStatusHistories",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_BookingStatusHistories_Bookings_BookingId",
          "columns": [
            "BookingId"
          ],
          "principalTable": "Bookings",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_BookingStatusHistories_BookingId",
          "columns": [
            "BookingId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "Bookings",
      "create": true,
      "columns": [
        {
          "name": "Id",
          "type": "integer",
          "nullable": false,
          "identity": "d",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CustomerId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PackageId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BookingDate",
          "type": "date",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StartTime",
          "type": "time without time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "EndTime",
          "type": "time without time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Location",
          "type": "character varying(500)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Notes",
          "type": "character varying(1000)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Status",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "TotalPrice",
          "type": "numeric(18,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PricingSnapshotJson",
          "type": "jsonb",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "UpdatedAt",
          "type": "timestamp with time zone",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_Bookings",
          "columns": [
            "Id"
          ],
          "primary": true
        },
        {
          "name": "AK_Bookings_Id_CustomerId_StudioId",
          "columns": [
            "Id",
            "CustomerId",
            "StudioId"
          ],
          "primary": false
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_Bookings_PhotographyPackages_PackageId",
          "columns": [
            "PackageId"
          ],
          "principalTable": "PhotographyPackages",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        },
        {
          "name": "FK_Bookings_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        },
        {
          "name": "FK_Bookings_Users_CustomerId",
          "columns": [
            "CustomerId"
          ],
          "principalTable": "Users",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        }
      ],
      "indexes": [
        {
          "name": "IX_Bookings_CustomerId",
          "columns": [
            "CustomerId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Bookings_PackageId",
          "columns": [
            "PackageId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Bookings_StudioId",
          "columns": [
            "StudioId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "Notifications",
      "create": true,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CustomerId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Title",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Message",
          "type": "character varying(1000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Type",
          "type": "character varying(60)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BookingId",
          "type": "integer",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "IsRead",
          "type": "boolean",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_Notifications",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_Notifications_Bookings_BookingId",
          "columns": [
            "BookingId"
          ],
          "principalTable": "Bookings",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "n"
        },
        {
          "name": "FK_Notifications_Users_CustomerId",
          "columns": [
            "CustomerId"
          ],
          "principalTable": "Users",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_Notifications_BookingId",
          "columns": [
            "BookingId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Notifications_CustomerId_CreatedAt",
          "columns": [
            "CustomerId",
            "CreatedAt"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Notifications_CustomerId_IsRead",
          "columns": [
            "CustomerId",
            "IsRead"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "PackageAddons",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PackageId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Name",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Description",
          "type": "character varying(1000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Price",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "UpdatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_PackageAddons",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_PackageAddons_PhotographyPackages_PackageId",
          "columns": [
            "PackageId"
          ],
          "principalTable": "PhotographyPackages",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_PackageAddons_PackageId",
          "columns": [
            "PackageId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "PhotographyPackageServices",
      "create": false,
      "columns": [
        {
          "name": "PhotographyPackageId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioServiceId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_PhotographyPackageServices",
          "columns": [
            "PhotographyPackageId",
            "StudioServiceId"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~",
          "columns": [
            "PhotographyPackageId"
          ],
          "principalTable": "PhotographyPackages",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        },
        {
          "name": "FK_PhotographyPackageServices_StudioServices_StudioServiceId",
          "columns": [
            "StudioServiceId"
          ],
          "principalTable": "StudioServices",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_PhotographyPackageServices_StudioServiceId",
          "columns": [
            "StudioServiceId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": true
        }
      ],
      "checks": []
    },
    {
      "name": "PhotographyPackages",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Name",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BasePrice",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ExtraHourRate",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "AdditionalPhotographerRate",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "DurationHours",
          "type": "numeric(5,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "EditedPhotoCount",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "AlbumIncluded",
          "type": "boolean",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "VideoIncluded",
          "type": "boolean",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PackageName",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Category",
          "type": "character varying(100)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Description",
          "type": "character varying(2000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Price",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Duration",
          "type": "character varying(100)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "NumberOfPhotographers",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CoverImageUrl",
          "type": "character varying(2048)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Status",
          "type": "character varying(20)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "UpdatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_PhotographyPackages",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_PhotographyPackages_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_PhotographyPackages_StudioId",
          "columns": [
            "StudioId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "Reviews",
      "create": true,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "BookingId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CustomerId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Rating",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Comment",
          "type": "character varying(2000)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_Reviews",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_Reviews_Bookings_BookingId_CustomerId_StudioId",
          "columns": [
            "BookingId",
            "CustomerId",
            "StudioId"
          ],
          "principalTable": "Bookings",
          "principalColumns": [
            "Id",
            "CustomerId",
            "StudioId"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        },
        {
          "name": "FK_Reviews_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        },
        {
          "name": "FK_Reviews_Users_CustomerId",
          "columns": [
            "CustomerId"
          ],
          "principalTable": "Users",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "r"
        }
      ],
      "indexes": [
        {
          "name": "IX_Reviews_BookingId",
          "columns": [
            "BookingId"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Reviews_BookingId_CustomerId_StudioId",
          "columns": [
            "BookingId",
            "CustomerId",
            "StudioId"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Reviews_CustomerId",
          "columns": [
            "CustomerId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        },
        {
          "name": "IX_Reviews_StudioId_CreatedAt",
          "columns": [
            "StudioId",
            "CreatedAt"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": [
        {
          "name": "CK_Reviews_Rating",
          "sql": "\u0022Rating\u0022 BETWEEN 1 AND 5",
          "catalogSql": "((\u0022Rating\u0022 \u003E= 1) AND (\u0022Rating\u0022 \u003C= 5))"
        }
      ]
    },
    {
      "name": "StudioAvailabilities",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": true
        },
        {
          "name": "Date",
          "type": "date",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "IsAvailable",
          "type": "boolean",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StartTime",
          "type": "time without time zone",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "EndTime",
          "type": "time without time zone",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Notes",
          "type": "character varying(1000)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_StudioAvailabilities",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_StudioAvailabilities_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_StudioAvailabilities_StudioId_Date",
          "columns": [
            "StudioId",
            "Date"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "StudioPortfolioImages",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioPortfolioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ImageUrl",
          "type": "character varying(2048)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "DisplayOrder",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_StudioPortfolioImages",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_StudioPortfolioImages_StudioPortfolios_StudioPortfolioId",
          "columns": [
            "StudioPortfolioId"
          ],
          "principalTable": "StudioPortfolios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": false,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_StudioPortfolioImages_StudioPortfolioId_DisplayOrder",
          "columns": [
            "StudioPortfolioId",
            "DisplayOrder"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "StudioPortfolios",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": true
        },
        {
          "name": "Title",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Description",
          "type": "character varying(1000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ImageUrl",
          "type": "character varying(2048)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Category",
          "type": "character varying(60)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "UpdatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_StudioPortfolios",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_StudioPortfolios_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_StudioPortfolios_StudioId",
          "columns": [
            "StudioId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "StudioServices",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StudioId",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": true
        },
        {
          "name": "ServiceName",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Description",
          "type": "character varying(1000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PackageDetails",
          "type": "text[]",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StartingPrice",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_StudioServices",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_StudioServices_Studios_StudioId",
          "columns": [
            "StudioId"
          ],
          "principalTable": "Studios",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_StudioServices_StudioId",
          "columns": [
            "StudioId"
          ],
          "unique": false,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "Studios",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "uuid",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "UserId",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": true
        },
        {
          "name": "StudioName",
          "type": "character varying(120)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Description",
          "type": "character varying(1000)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Location",
          "type": "character varying(160)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Address",
          "type": "character varying(240)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ContactNumber",
          "type": "character varying(30)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Email",
          "type": "character varying(254)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "ExperienceYears",
          "type": "integer",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PhotographyTypes",
          "type": "character varying(500)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "StartingPrice",
          "type": "numeric(12,2)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "LogoUrl",
          "type": "character varying(2048)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CoverPhotoUrl",
          "type": "character varying(2048)",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_Studios",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_Studios_Users_UserId",
          "columns": [
            "UserId"
          ],
          "principalTable": "Users",
          "principalColumns": [
            "Id"
          ],
          "reconcileWhenMissing": true,
          "deleteAction": "c"
        }
      ],
      "indexes": [
        {
          "name": "IX_Studios_UserId",
          "columns": [
            "UserId"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": true,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    },
    {
      "name": "Users",
      "create": false,
      "columns": [
        {
          "name": "Id",
          "type": "integer",
          "nullable": false,
          "identity": "d",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "FullName",
          "type": "text",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Email",
          "type": "text",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "PhoneNumber",
          "type": "character varying(30)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": true,
          "reconcileNotNull": false
        },
        {
          "name": "ProfilePhotoUrl",
          "type": "character varying(2048)",
          "nullable": true,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": true,
          "reconcileNotNull": false
        },
        {
          "name": "PasswordHash",
          "type": "text",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "Role",
          "type": "text",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        },
        {
          "name": "CreatedAt",
          "type": "timestamp with time zone",
          "nullable": false,
          "identity": "",
          "generated": "",
          "defaultSql": null,
          "add": false,
          "reconcileNotNull": false
        }
      ],
      "keys": [
        {
          "name": "PK_Users",
          "columns": [
            "Id"
          ],
          "primary": true
        }
      ],
      "foreignKeys": [],
      "indexes": [
        {
          "name": "IX_Users_Email",
          "columns": [
            "Email"
          ],
          "unique": true,
          "filter": null,
          "reconcileKnownPartial": false,
          "reconcileWhenMissing": false
        }
      ],
      "checks": []
    }
  ]
}$model$::jsonb;
    planned_tables text[] := ARRAY[]::text[];
    planned_user_columns text[] := ARRAY[]::text[];
    strict_constraint record;
    strict_index record;
    strict_sequence record;
    strict_item jsonb;
    strict_column record;
    table_def jsonb;
    item jsonb;
    table_oid oid;
    column_record record;
    object_name text;
    expected_columns text[];
    principal_columns text[];
    package_fk record;
    package_fk_present boolean := false;
    orphan_count bigint;
    service_fk record;
    service_fk_present boolean := false;
    service_orphan_count bigint;
    service_index record;
    service_index_present boolean := false;
    studio_fk record;
    studio_fk_present boolean := false;
    studio_null_count bigint;
    studio_orphan_count bigint;
    availability_fk record;
    availability_fk_present boolean := false;
    availability_not_null_required boolean := false;
    availability_null_count bigint;
    availability_orphan_count bigint;
    portfolio_fk record;
    portfolio_fk_present boolean := false;
    portfolio_not_null_required boolean := false;
    portfolio_null_count bigint;
    portfolio_orphan_count bigint;
    serviceOwner_fk record;
    serviceOwner_fk_present boolean := false;
    serviceOwner_not_null_required boolean := false;
    serviceOwner_null_count bigint;
    serviceOwner_orphan_count bigint;
    ownership_fk record;
    ownership_fk_present boolean := false;
    ownership_not_null_required boolean := false;
    ownership_null_count bigint;
    ownership_orphan_count bigint;
    ownership_duplicate_count bigint;
    ownership_index record;
    ownership_index_present boolean := false;
    ownership_index_replace boolean := false;

BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'public') THEN
        RAISE EXCEPTION 'Expected public schema is missing. Stop and review.';
    END IF;
    IF to_regclass('public."__EFMigrationsHistory"') IS NULL THEN
        RAISE EXCEPTION 'Existing EF migration history is missing. Stop and review.';
    END IF;
    IF (SELECT count(*) FROM public."__EFMigrationsHistory") <> 1 OR
       NOT EXISTS (SELECT 1 FROM public."__EFMigrationsHistory"
                   WHERE "MigrationId" = '202609020001_AddPortfolioImages') THEN
        RAISE EXCEPTION 'Unexpected migration history. Expected only AddPortfolioImages; no history will be rewritten.';
    END IF;

    FOR table_def IN SELECT value FROM jsonb_array_elements(expected_model->'tables') LOOP
        object_name := table_def->>'name';
        -- Reject same-name objects in another user schema instead of guessing a search path.
        IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE c.relname = object_name AND n.nspname <> 'public'
                     AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%') THEN
            RAISE EXCEPTION 'Ambiguous schema for %. Stop and review.', object_name;
        END IF;
        table_oid := to_regclass(format('public.%I', object_name));
        IF (table_def->>'create')::boolean AND table_oid IS NULL THEN
            IF EXISTS (
                SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = 'public' AND t.typname = object_name) THEN
                RAISE EXCEPTION 'Target type % conflicts with absent table. Stop; never replace or convert it.', object_name;
            END IF;
            -- Detect conflicting index/sequence names before executing any DDL.
            FOR item IN SELECT value FROM jsonb_array_elements(table_def->'indexes')
                        UNION ALL SELECT value FROM jsonb_array_elements(table_def->'keys') LOOP
                IF to_regclass(format('public.%I', item->>'name')) IS NOT NULL THEN
                    RAISE EXCEPTION 'Target index/key name % already exists. Stop and review.', item->>'name';
                END IF;
            END LOOP;
            IF object_name IN ('Bookings', 'BookingLocations', 'BookingStatusHistories') AND
               to_regclass(format('public.%I', object_name || '_Id_seq')) IS NOT NULL THEN
                RAISE EXCEPTION 'Target identity sequence for % already exists. Stop and review.', object_name;
            END IF;
            planned_tables := array_append(planned_tables, object_name);
            RAISE NOTICE 'Planned creation of absent table public.%', object_name;
            CONTINUE;
        END IF;

        IF table_oid IS NULL OR NOT EXISTS (
            SELECT 1 FROM pg_class WHERE oid = table_oid AND relkind = 'r' AND relpersistence = 'p') THEN
            RAISE EXCEPTION 'Expected permanent ordinary table public.% is missing or incompatible.', object_name;
        END IF;
        IF (table_def->>'create')::boolean THEN
            -- Existing reconciliation targets are accepted only as the complete
            -- final model. Missing indexes/keys or unexpected objects are NOT repaired.
            IF EXISTS (SELECT 1 FROM pg_class tbl WHERE tbl.oid = table_oid
                       AND (tbl.relispartition OR tbl.reloftype <> 0 OR tbl.relrowsecurity
                            OR tbl.relforcerowsecurity OR tbl.relreplident <> 'd'))
               OR EXISTS (SELECT 1 FROM pg_inherits WHERE inhrelid = table_oid OR inhparent = table_oid)
               OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = table_oid AND NOT tgisinternal)
               OR EXISTS (SELECT 1 FROM pg_rewrite WHERE ev_class = table_oid)
               OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = table_oid) THEN
                RAISE EXCEPTION 'Unexpected target table behavior on %. Stop; never replace or convert it.', object_name;
            END IF;
            IF ARRAY(SELECT attr.attname::text FROM pg_attribute attr
                     WHERE attr.attrelid = table_oid AND attr.attnum > 0 AND NOT attr.attisdropped
                     ORDER BY attr.attnum)
               IS DISTINCT FROM ARRAY(SELECT col->>'name' FROM jsonb_array_elements(table_def->'columns') col) THEN
                RAISE EXCEPTION 'Exact target column set/order mismatch on %.', object_name;
            END IF;
            FOR strict_item IN SELECT value FROM jsonb_array_elements(table_def->'columns') LOOP
                SELECT attr.*, format_type(attr.atttypid, attr.atttypmod) AS type_name,
                       pg_get_expr(def.adbin, def.adrelid) AS default_sql,
                       typ.typcollation AS expected_collation
                INTO strict_column
                FROM pg_attribute attr JOIN pg_type typ ON typ.oid = attr.atttypid
                LEFT JOIN pg_attrdef def ON def.adrelid = attr.attrelid AND def.adnum = attr.attnum
                WHERE attr.attrelid = table_oid AND attr.attname = strict_item->>'name'
                  AND attr.attnum > 0 AND NOT attr.attisdropped;
                IF strict_column.type_name IS DISTINCT FROM strict_item->>'type'
                   OR strict_column.attnotnull IS DISTINCT FROM (NOT (strict_item->>'nullable')::boolean)
                   OR strict_column.attgenerated::text IS DISTINCT FROM strict_item->>'generated'
                   OR strict_column.attidentity::text IS DISTINCT FROM strict_item->>'identity'
                   OR strict_column.default_sql IS DISTINCT FROM strict_item->>'defaultSql'
                   OR strict_column.attcollation <> strict_column.expected_collation THEN
                    RAISE EXCEPTION 'Exact target column semantics mismatch at %.%.', object_name, strict_item->>'name';
                END IF;
                IF strict_item->>'identity' <> '' THEN
                    SELECT seq.*, seq_tbl.relkind, seq_tbl.relpersistence INTO strict_sequence
                    FROM pg_sequence seq JOIN pg_class seq_tbl ON seq_tbl.oid = seq.seqrelid
                    JOIN pg_depend dep ON dep.classid = 'pg_class'::regclass AND dep.objid = seq.seqrelid
                      AND dep.refclassid = 'pg_class'::regclass AND dep.refobjid = table_oid
                      AND dep.refobjsubid = strict_column.attnum AND dep.deptype = 'i'
                    WHERE seq.seqrelid = to_regclass(pg_get_serial_sequence(format('public.%I', object_name), strict_item->>'name'));
                    IF NOT FOUND THEN
                        RAISE EXCEPTION 'Missing/incorrect target identity sequence at %.%.', object_name, strict_item->>'name';
                    END IF;
                    IF strict_sequence.relkind <> 'S' OR strict_sequence.relpersistence <> 'p'
                       OR strict_sequence.seqtypid <> 'integer'::regtype
                       OR strict_sequence.seqstart <> 1 OR strict_sequence.seqincrement <> 1
                       OR strict_sequence.seqmin <> 1 OR strict_sequence.seqmax <> 2147483647
                       OR strict_sequence.seqcache <> 1 OR strict_sequence.seqcycle THEN
                        RAISE EXCEPTION 'Incompatible target identity sequence at %.%.', object_name, strict_item->>'name';
                    END IF;
                END IF;
            END LOOP;

            -- NOT NULL constraints have their own catalog entries on PostgreSQL 18;
            -- they are checked by the exact column nullability validation above.
            IF EXISTS (SELECT 1 FROM pg_constraint nn
                       WHERE nn.conrelid = table_oid AND nn.contype = 'n'
                         AND (NOT nn.convalidated OR NOT coalesce((to_jsonb(nn)->>'conenforced')::boolean, true)
                              OR cardinality(nn.conkey) <> 1 OR NOT EXISTS (
                                  SELECT 1 FROM pg_attribute attr
                                  WHERE attr.attrelid = table_oid AND attr.attnum = nn.conkey[1]
                                    AND attr.attnotnull AND NOT attr.attisdropped))) THEN
                RAISE EXCEPTION 'Incompatible target NOT NULL constraint on %.', object_name;
            END IF;
            IF (SELECT count(*) FROM pg_constraint WHERE conrelid = table_oid AND contype <> 'n')
                <> jsonb_array_length(table_def->'keys') + jsonb_array_length(table_def->'foreignKeys')
                   + jsonb_array_length(table_def->'checks') THEN
                RAISE EXCEPTION 'Missing/unexpected target constraints on %.', object_name;
            END IF;
            FOR strict_constraint IN SELECT * FROM pg_constraint WHERE conrelid = table_oid AND contype <> 'n' LOOP
                IF NOT strict_constraint.convalidated OR strict_constraint.condeferrable
                   OR strict_constraint.condeferred OR strict_constraint.conislocal IS NOT TRUE
                   OR strict_constraint.coninhcount <> 0
                   OR NOT coalesce((to_jsonb(strict_constraint)->>'conenforced')::boolean, true) THEN
                    RAISE EXCEPTION 'Incompatible target constraint state %.%.', object_name, strict_constraint.conname;
                END IF;
                IF strict_constraint.contype IN ('p', 'u') THEN
                    SELECT value INTO strict_item FROM jsonb_array_elements(table_def->'keys')
                    WHERE value->>'name' = strict_constraint.conname;
                    IF NOT FOUND THEN RAISE EXCEPTION 'Unexpected target key %.%.', object_name, strict_constraint.conname; END IF;
                    IF strict_constraint.contype::text <> (CASE WHEN (strict_item->>'primary')::boolean THEN 'p' ELSE 'u' END)
                       OR NOT EXISTS (SELECT 1 FROM pg_class key_tbl
                                      WHERE key_tbl.oid = strict_constraint.conindid AND key_tbl.relname = strict_constraint.conname)
                       OR ARRAY(SELECT attr.attname::text FROM unnest(strict_constraint.conkey) WITH ORDINALITY key_col(num, pos)
                                JOIN pg_attribute attr ON attr.attrelid = table_oid AND attr.attnum = key_col.num ORDER BY key_col.pos)
                          IS DISTINCT FROM ARRAY(SELECT jsonb_array_elements_text(strict_item->'columns')) THEN
                        RAISE EXCEPTION 'Incompatible target key definition %.%.', object_name, strict_constraint.conname;
                    END IF;
                ELSIF strict_constraint.contype = 'f' THEN
                    SELECT value INTO strict_item FROM jsonb_array_elements(table_def->'foreignKeys')
                    WHERE value->>'name' = strict_constraint.conname;
                    IF NOT FOUND THEN RAISE EXCEPTION 'Unexpected target FK %.%.', object_name, strict_constraint.conname; END IF;
                    IF strict_constraint.confrelid IS DISTINCT FROM to_regclass(format('public.%I', strict_item->>'principalTable'))
                       OR strict_constraint.confmatchtype <> 's' OR strict_constraint.confupdtype <> 'a'
                       OR strict_constraint.confdeltype::text IS DISTINCT FROM strict_item->>'deleteAction'
                       OR strict_constraint.confdelsetcols IS NOT NULL
                       OR coalesce((to_jsonb(strict_constraint)->>'conperiod')::boolean, false)
                       OR ARRAY(SELECT attr.attname::text FROM unnest(strict_constraint.conkey) WITH ORDINALITY key_col(num, pos)
                                JOIN pg_attribute attr ON attr.attrelid = table_oid AND attr.attnum = key_col.num ORDER BY key_col.pos)
                          IS DISTINCT FROM ARRAY(SELECT jsonb_array_elements_text(strict_item->'columns'))
                       OR ARRAY(SELECT attr.attname::text FROM unnest(strict_constraint.confkey) WITH ORDINALITY key_col(num, pos)
                                JOIN pg_attribute attr ON attr.attrelid = strict_constraint.confrelid AND attr.attnum = key_col.num ORDER BY key_col.pos)
                          IS DISTINCT FROM ARRAY(SELECT jsonb_array_elements_text(strict_item->'principalColumns')) THEN
                        RAISE EXCEPTION 'Incompatible target FK definition %.%.', object_name, strict_constraint.conname;
                    END IF;
                ELSIF strict_constraint.contype = 'c' THEN
                    SELECT value INTO strict_item FROM jsonb_array_elements(table_def->'checks')
                    WHERE value->>'name' = strict_constraint.conname;
                    IF NOT FOUND THEN RAISE EXCEPTION 'Unexpected target CHECK %.%.', object_name, strict_constraint.conname; END IF;
                    IF strict_constraint.connoinherit OR pg_get_expr(strict_constraint.conbin, table_oid, false)
                       IS DISTINCT FROM strict_item->>'catalogSql' THEN
                        RAISE EXCEPTION 'Incompatible target CHECK definition %.%.', object_name, strict_constraint.conname;
                    END IF;
                ELSE
                    RAISE EXCEPTION 'Unexpected target constraint kind on %.', object_name;
                END IF;
            END LOOP;

            IF (SELECT count(*) FROM pg_index WHERE indrelid = table_oid)
               <> jsonb_array_length(table_def->'keys') + jsonb_array_length(table_def->'indexes') THEN
                RAISE EXCEPTION 'Missing/unexpected target indexes on %.', object_name;
            END IF;
            FOR strict_index IN
                SELECT idx.*, idx_tbl.relname, idx_tbl.relkind, idx_tbl.relpersistence, am.amname
                FROM pg_index idx JOIN pg_class idx_tbl ON idx_tbl.oid = idx.indexrelid
                JOIN pg_am am ON am.oid = idx_tbl.relam WHERE idx.indrelid = table_oid
            LOOP
                SELECT definition INTO strict_item FROM (
                    SELECT value AS definition FROM jsonb_array_elements(table_def->'indexes')
                    UNION ALL SELECT value || jsonb_build_object('unique', true) FROM jsonb_array_elements(table_def->'keys')
                ) definitions WHERE definition->>'name' = strict_index.relname;
                IF NOT FOUND THEN RAISE EXCEPTION 'Unexpected target index %.%.', object_name, strict_index.relname; END IF;
                IF strict_index.relkind <> 'i' OR strict_index.relpersistence <> 'p' OR strict_index.amname <> 'btree'
                   OR NOT strict_index.indisvalid OR NOT strict_index.indisready OR NOT strict_index.indislive
                   OR NOT strict_index.indimmediate OR strict_index.indisexclusion OR strict_index.indnullsnotdistinct
                   OR strict_index.indisclustered OR strict_index.indisreplident
                   OR strict_index.indisunique IS DISTINCT FROM (strict_item->>'unique')::boolean
                   OR strict_index.indisprimary IS DISTINCT FROM coalesce((strict_item->>'primary')::boolean, false)
                   OR strict_index.indexprs IS NOT NULL OR strict_index.indpred IS NOT NULL
                   OR strict_index.indnatts <> strict_index.indnkeyatts
                   OR strict_index.indnkeyatts <> jsonb_array_length(strict_item->'columns')
                   OR EXISTS (SELECT 1 FROM unnest(strict_index.indoption) opt WHERE opt <> 0)
                   OR EXISTS (SELECT 1 FROM unnest(strict_index.indclass) class_oid
                              JOIN pg_opclass opclass ON opclass.oid = class_oid
                              WHERE NOT opclass.opcdefault OR opclass.opcnamespace <> 'pg_catalog'::regnamespace)
                   OR EXISTS (SELECT 1 FROM unnest(strict_index.indkey, strict_index.indcollation) key_col(num, coll)
                              JOIN pg_attribute attr ON attr.attrelid = table_oid AND attr.attnum = key_col.num
                              WHERE key_col.coll <> attr.attcollation)
                   OR ARRAY(SELECT attr.attname::text FROM unnest(strict_index.indkey) WITH ORDINALITY key_col(num, pos)
                            JOIN pg_attribute attr ON attr.attrelid = table_oid AND attr.attnum = key_col.num ORDER BY key_col.pos)
                      IS DISTINCT FROM ARRAY(SELECT jsonb_array_elements_text(strict_item->'columns')) THEN
                    RAISE EXCEPTION 'Incompatible target index %.%.', object_name, strict_index.relname;
                END IF;
            END LOOP;
            RAISE NOTICE 'Already reconciled target public.% verified exactly; no creation planned.', object_name;
            CONTINUE;
        END IF;
        FOR item IN SELECT value FROM jsonb_array_elements(table_def->'columns') LOOP
            SELECT format_type(a.atttypid, a.atttypmod) AS type_name, a.attnotnull,
                   a.attgenerated, a.attidentity, pg_get_expr(d.adbin, d.adrelid) AS default_sql
              INTO column_record
              FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
             WHERE a.attrelid = table_oid AND a.attname = item->>'name'
               AND a.attnum > 0 AND NOT a.attisdropped;
            IF (item->>'add')::boolean THEN
                IF NOT FOUND THEN
                    planned_user_columns := array_append(planned_user_columns, item->>'name');
                    RAISE NOTICE 'Planned addition of %.%', object_name, item->>'name';
                ELSIF column_record.type_name IS DISTINCT FROM item->>'type'
                   OR column_record.attnotnull IS DISTINCT FROM (NOT (item->>'nullable')::boolean)
                   OR column_record.attgenerated <> '' OR column_record.attidentity <> ''
                   OR column_record.default_sql IS NOT NULL THEN
                    RAISE EXCEPTION 'Incompatible already-present target column %.%. Stop; never replace it.', object_name, item->>'name';
                END IF;
            ELSE
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Required existing column %.% is missing. Stop and review.', object_name, item->>'name';
                END IF;
                -- Only this approved required UUID may temporarily be nullable.
                -- Do not bypass type/generated checks or accept a model change.
                IF object_name = 'StudioAvailabilities' AND item->>'name' = 'StudioId'
                   AND coalesce((item->>'reconcileNotNull')::boolean, false) THEN
                    IF item->>'type' <> 'uuid' OR (item->>'nullable')::boolean
                       OR column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''
                       OR column_record.attidentity <> '' THEN
                        RAISE EXCEPTION 'Incompatible StudioAvailabilities.StudioId definition. Only ordinary uuid NULL -> NOT NULL is approved.';
                    END IF;
                    availability_not_null_required := NOT column_record.attnotnull;
                END IF;
                IF object_name = 'StudioPortfolios' AND item->>'name' = 'StudioId'
                   AND coalesce((item->>'reconcileNotNull')::boolean, false) THEN
                    IF item->>'type' <> 'uuid' OR (item->>'nullable')::boolean
                       OR column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''
                       OR column_record.attidentity <> '' THEN
                        RAISE EXCEPTION 'Incompatible StudioPortfolios.StudioId definition. Only ordinary uuid NULL -> NOT NULL is approved.';
                    END IF;
                    portfolio_not_null_required := NOT column_record.attnotnull;
                END IF;
                IF object_name = 'Studios' AND item->>'name' = 'UserId'
                   AND coalesce((item->>'reconcileNotNull')::boolean, false) THEN
                    IF item->>'type' <> 'integer' OR (item->>'nullable')::boolean
                       OR column_record.type_name <> 'integer' OR column_record.attgenerated <> ''
                       OR column_record.attidentity <> '' THEN
                        RAISE EXCEPTION 'Incompatible Studios.UserId definition. Only ordinary integer NULL -> NOT NULL is approved.';
                    END IF;
                    ownership_not_null_required := NOT column_record.attnotnull;
                END IF;
                IF object_name = 'StudioServices' AND item->>'name' = 'StudioId'
                   AND coalesce((item->>'reconcileNotNull')::boolean, false) THEN
                    IF item->>'type' <> 'uuid' OR (item->>'nullable')::boolean
                       OR column_record.type_name <> 'uuid' OR column_record.attgenerated <> ''
                       OR column_record.attidentity <> '' THEN
                        RAISE EXCEPTION 'Incompatible StudioServices.StudioId definition. Only ordinary uuid NULL -> NOT NULL is approved.';
                    END IF;
                    serviceOwner_not_null_required := NOT column_record.attnotnull;
                END IF;
                IF column_record.type_name <> item->>'type' OR
                   (column_record.attnotnull <> (NOT (item->>'nullable')::boolean)
                    AND NOT (object_name = 'StudioAvailabilities' AND item->>'name' = 'StudioId'
                             AND availability_not_null_required)
                    AND NOT (object_name = 'StudioPortfolios' AND item->>'name' = 'StudioId'
                             AND portfolio_not_null_required)
                    AND NOT (object_name = 'StudioServices' AND item->>'name' = 'StudioId'
                             AND serviceOwner_not_null_required)
                    AND NOT (object_name = 'Studios' AND item->>'name' = 'UserId'
                             AND ownership_not_null_required)) OR
                   column_record.attgenerated <> '' THEN
                    RAISE EXCEPTION 'Existing type/nullability/generated-column conflict at %.%. Stop and review.', object_name, item->>'name';
                END IF;
                IF object_name = 'Users' AND item->>'name' = 'Id' AND
                   column_record.attidentity = '' AND
                   coalesce(column_record.default_sql, '') NOT LIKE 'nextval(%' THEN
                    RAISE EXCEPTION 'Users.Id must already have identity/sequence generation. Stop and review.';
                END IF;
            END IF;
        END LOOP;

        -- Match definitions rather than names: manual SQL may use e.g. Users_pkey.
        FOR item IN SELECT value FROM jsonb_array_elements(table_def->'keys') LOOP
            expected_columns := ARRAY(SELECT jsonb_array_elements_text(item->'columns'));
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                WHERE c.conrelid = table_oid
                  AND c.contype = CASE WHEN (item->>'primary')::boolean THEN 'p'::"char" ELSE 'u'::"char" END
                  AND c.convalidated AND NOT c.condeferrable
                  AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(num, pos)
                            JOIN pg_attribute a ON a.attrelid = table_oid AND a.attnum = k.num ORDER BY k.pos) = expected_columns
            ) THEN
                RAISE EXCEPTION 'Missing/incompatible existing key %.% (definition checked). Stop and review.', object_name, item->>'name';
            END IF;
        END LOOP;
        FOR item IN SELECT value FROM jsonb_array_elements(table_def->'foreignKeys') LOOP
            -- These exact approved exceptions are checked after full structural validation.
            IF object_name = 'StudioAvailabilities' AND
               item->>'name' = 'FK_StudioAvailabilities_Studios_StudioId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            IF object_name = 'StudioPortfolios' AND
               item->>'name' = 'FK_StudioPortfolios_Studios_StudioId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            IF object_name = 'Studios' AND
               item->>'name' = 'FK_Studios_Users_UserId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            IF object_name = 'StudioServices' AND
               item->>'name' = 'FK_StudioServices_Studios_StudioId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            IF object_name = 'PhotographyPackages' AND
               item->>'name' = 'FK_PhotographyPackages_Studios_StudioId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            IF object_name = 'PhotographyPackageServices' AND
               item->>'name' IN ('FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~',
                                'FK_PhotographyPackageServices_StudioServices_StudioServiceId') AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            expected_columns := ARRAY(SELECT jsonb_array_elements_text(item->'columns'));
            principal_columns := ARRAY(SELECT jsonb_array_elements_text(item->'principalColumns'));
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                WHERE c.conrelid = table_oid AND c.contype = 'f' AND c.convalidated AND NOT c.condeferrable
                  AND c.confrelid = to_regclass(format('public.%I', item->>'principalTable'))
                  AND c.confdeltype::text = item->>'deleteAction' AND c.confupdtype = 'a' AND c.confmatchtype = 's'
                  AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(num, pos)
                            JOIN pg_attribute a ON a.attrelid = table_oid AND a.attnum = k.num ORDER BY k.pos) = expected_columns
                  AND ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(num, pos)
                            JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.num ORDER BY k.pos) = principal_columns
            ) THEN
                RAISE EXCEPTION 'Missing/incompatible existing foreign key %.%. Stop and review; do not invent ownership IDs.', object_name, item->>'name';
            END IF;
        END LOOP;
        FOR item IN SELECT value FROM jsonb_array_elements(table_def->'indexes') LOOP
            IF object_name = 'Studios' AND item->>'name' = 'IX_Studios_UserId'
               AND coalesce((item->>'reconcileKnownPartial')::boolean, false) THEN
                CONTINUE;
            END IF;
            IF object_name = 'PhotographyPackageServices' AND
               item->>'name' = 'IX_PhotographyPackageServices_StudioServiceId' AND
               (item->>'reconcileWhenMissing')::boolean THEN
                CONTINUE;
            END IF;
            expected_columns := ARRAY(SELECT jsonb_array_elements_text(item->'columns'));
            IF NOT EXISTS (
                SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
                JOIN pg_am am ON am.oid = ic.relam
                WHERE i.indrelid = table_oid AND i.indisvalid AND i.indisready AND am.amname = 'btree'
                  AND i.indisunique = (item->>'unique')::boolean AND i.indexprs IS NULL
                  AND i.indpred IS NULL AND item->>'filter' IS NULL
                  AND i.indnkeyatts = cardinality(expected_columns)
                  AND NOT EXISTS (SELECT 1 FROM unnest(i.indoption) opt WHERE opt <> 0)
                  -- indkey includes INCLUDE columns; only the first indnkeyatts are keys.
                  AND ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
                            JOIN pg_attribute a ON a.attrelid = table_oid AND a.attnum = k.num
                            WHERE k.pos <= i.indnkeyatts ORDER BY k.pos) = expected_columns
            ) THEN
                RAISE EXCEPTION 'Missing/incompatible existing index %.%. Stop and review.', object_name, item->>'name';
            END IF;
        END LOOP;
    END LOOP;
    -- Both tables, all mapped columns, primary keys and non-exempt indexes have passed above.
    -- Consider wrong-target/wrong-column/composite/name-collision constraints too.
    FOR package_fk IN
        SELECT c.* FROM pg_constraint c
        WHERE c.conrelid = 'public."PhotographyPackageServices"'::regclass
          AND (
              c.conname = 'FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~'
              OR (c.contype = 'f' AND (
                  c.confrelid = 'public."PhotographyPackages"'::regclass
                  OR EXISTS (SELECT 1 FROM pg_attribute a
                             WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
                               AND a.attname = 'PhotographyPackageId')
                  OR starts_with(c.conname::text, 'FK_PhotographyPackageServices_PhotographyPackages_')
              ))
          )
    LOOP
        IF NOT (
            package_fk.contype = 'f' AND package_fk.convalidated
            AND NOT package_fk.condeferrable AND NOT package_fk.condeferred
            AND package_fk.confrelid = 'public."PhotographyPackages"'::regclass
            AND package_fk.confdeltype = 'c' AND package_fk.confupdtype = 'a'
            AND package_fk.confmatchtype = 's'
            AND ARRAY(SELECT a.attname::text FROM unnest(package_fk.conkey) WITH ORDINALITY k(num, pos)
                      JOIN pg_attribute a ON a.attrelid = package_fk.conrelid AND a.attnum = k.num
                      ORDER BY k.pos) = ARRAY['PhotographyPackageId']::text[]
            AND ARRAY(SELECT a.attname::text FROM unnest(package_fk.confkey) WITH ORDINALITY k(num, pos)
                      JOIN pg_attribute a ON a.attrelid = package_fk.confrelid AND a.attnum = k.num
                      ORDER BY k.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible package-service FK or constraint name collision: %. Stop; never replace it.', package_fk.conname;
        END IF;
        package_fk_present := true;
    END LOOP;

    SELECT count(*) INTO orphan_count
    FROM public."PhotographyPackageServices" ps
    WHERE NOT EXISTS (SELECT 1 FROM public."PhotographyPackages" p
                      WHERE p."Id" = ps."PhotographyPackageId");
    IF orphan_count <> 0 THEN
        RAISE EXCEPTION 'Package-service orphan rows: %. Stop; never delete or repair data automatically.', orphan_count;
    END IF;
    -- Both tables, all mapped columns, primary keys and non-exempt indexes have passed above.
    -- Consider wrong-target/wrong-column/composite/name-collision constraints too.
    FOR service_fk IN
        SELECT c.* FROM pg_constraint c
        WHERE c.conrelid = 'public."PhotographyPackageServices"'::regclass
          AND (
              c.conname = 'FK_PhotographyPackageServices_StudioServices_StudioServiceId'
              OR (c.contype = 'f' AND (
                  c.confrelid = 'public."StudioServices"'::regclass
                  OR EXISTS (SELECT 1 FROM pg_attribute a
                             WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
                               AND a.attname = 'StudioServiceId')
                  OR starts_with(c.conname::text, 'FK_PhotographyPackageServices_StudioServices_')
              ))
          )
    LOOP
        IF NOT (
            service_fk.contype = 'f' AND service_fk.convalidated
            AND NOT service_fk.condeferrable AND NOT service_fk.condeferred
            AND service_fk.confrelid = 'public."StudioServices"'::regclass
            AND service_fk.confdeltype = 'c' AND service_fk.confupdtype = 'a'
            AND service_fk.confmatchtype = 's'
            AND ARRAY(SELECT a.attname::text FROM unnest(service_fk.conkey) WITH ORDINALITY k(num, pos)
                      JOIN pg_attribute a ON a.attrelid = service_fk.conrelid AND a.attnum = k.num
                      ORDER BY k.pos) = ARRAY['StudioServiceId']::text[]
            AND ARRAY(SELECT a.attname::text FROM unnest(service_fk.confkey) WITH ORDINALITY k(num, pos)
                      JOIN pg_attribute a ON a.attrelid = service_fk.confrelid AND a.attnum = k.num
                      ORDER BY k.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible studio-service FK or constraint name collision: %. Stop; never replace it.', service_fk.conname;
        END IF;
        service_fk_present := true;
    END LOOP;

    SELECT count(*) INTO service_orphan_count
    FROM public."PhotographyPackageServices" ps
    WHERE NOT EXISTS (SELECT 1 FROM public."StudioServices" p
                      WHERE p."Id" = ps."StudioServiceId");
    IF service_orphan_count <> 0 THEN
        RAISE EXCEPTION 'Studio-service orphan rows: %. Stop; never delete or repair data automatically.', service_orphan_count;
    END IF;
    -- All structural checks above still apply, including uuid NOT NULL columns
    -- and the existing child index. Require an eligible parent key/index too.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint key_constraint
        JOIN pg_index key_index ON key_index.indexrelid = key_constraint.conindid
        JOIN pg_attribute attr ON attr.attrelid = key_constraint.conrelid
          AND attr.attname = 'Id' AND attr.attnum > 0 AND NOT attr.attisdropped
        WHERE key_constraint.conrelid = 'public."Studios"'::regclass
          AND key_constraint.contype IN ('p', 'u')
          AND key_constraint.convalidated AND NOT key_constraint.condeferrable
          AND NOT key_constraint.condeferred
          AND key_constraint.conkey = ARRAY[attr.attnum]::smallint[]
          AND key_index.indrelid = key_constraint.conrelid
          AND key_index.indisunique AND key_index.indisvalid AND key_index.indisready
          AND key_index.indislive AND key_index.indimmediate
          AND key_index.indpred IS NULL AND key_index.indexprs IS NULL
          AND key_index.indnkeyatts = 1 AND key_index.indkey[0] = attr.attnum
    ) THEN
        RAISE EXCEPTION 'Studios.Id lacks a valid eligible PK/unique key. Stop and review.';
    END IF;
    FOR studio_fk IN
        SELECT constraint_row.* FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'public."PhotographyPackages"'::regclass
          AND (constraint_row.conname = 'FK_PhotographyPackages_Studios_StudioId'
            OR (constraint_row.contype = 'f' AND (
                constraint_row.confrelid = 'public."Studios"'::regclass
                OR starts_with(constraint_row.conname::text, 'FK_PhotographyPackages_Studios_')
                OR EXISTS (SELECT 1 FROM pg_attribute attr
                    WHERE attr.attrelid = constraint_row.conrelid
                      AND attr.attnum = ANY(constraint_row.conkey) AND attr.attname = 'StudioId'))))
    LOOP
        IF NOT (
            studio_fk.contype = 'f' AND studio_fk.convalidated
            AND NOT studio_fk.condeferrable AND NOT studio_fk.condeferred
            AND coalesce((to_jsonb(studio_fk)->>'conenforced')::boolean, true)
            AND studio_fk.confrelid = 'public."Studios"'::regclass
            AND studio_fk.confdeltype = 'c' AND studio_fk.confupdtype = 'a'
            AND studio_fk.confmatchtype = 's'
            AND ARRAY(SELECT attr.attname::text FROM unnest(studio_fk.conkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = studio_fk.conrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['StudioId']::text[]
            AND ARRAY(SELECT attr.attname::text FROM unnest(studio_fk.confkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = studio_fk.confrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible package-studio FK or constraint name collision: %. Stop; never replace it.', studio_fk.conname;
        END IF;
        studio_fk_present := true;
    END LOOP;
    SELECT count(*) INTO studio_null_count FROM public."PhotographyPackages"
    WHERE "StudioId" IS NULL;
    IF studio_null_count <> 0 THEN
        RAISE EXCEPTION 'PhotographyPackages NULL StudioId rows: %. Stop; never repair data automatically.', studio_null_count;
    END IF;
    SELECT count(*) INTO studio_orphan_count FROM public."PhotographyPackages" package_row
    WHERE package_row."StudioId" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public."Studios" studio_row WHERE studio_row."Id" = package_row."StudioId");
    IF studio_orphan_count <> 0 THEN
        RAISE EXCEPTION 'PhotographyPackages orphan StudioId rows: %. Stop; never repair data automatically.', studio_orphan_count;
    END IF;
    -- The shared Studios.Id eligible-key guard above applies to this relationship too.
    FOR availability_fk IN
        SELECT constraint_row.* FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'public."StudioAvailabilities"'::regclass
          AND (constraint_row.conname = 'FK_StudioAvailabilities_Studios_StudioId'
            OR (constraint_row.contype = 'f' AND (
                constraint_row.confrelid = 'public."Studios"'::regclass
                OR starts_with(constraint_row.conname::text, 'FK_StudioAvailabilities_Studios_')
                OR EXISTS (SELECT 1 FROM pg_attribute attr
                    WHERE attr.attrelid = constraint_row.conrelid
                      AND attr.attnum = ANY(constraint_row.conkey) AND attr.attname = 'StudioId'))))
    LOOP
        IF NOT (
            availability_fk.contype = 'f' AND availability_fk.convalidated
            AND NOT availability_fk.condeferrable AND NOT availability_fk.condeferred
            AND coalesce((to_jsonb(availability_fk)->>'conenforced')::boolean, true)
            AND availability_fk.confrelid = 'public."Studios"'::regclass
            AND availability_fk.confdeltype = 'c' AND availability_fk.confupdtype = 'a'
            AND availability_fk.confmatchtype = 's'
            AND ARRAY(SELECT attr.attname::text FROM unnest(availability_fk.conkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = availability_fk.conrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['StudioId']::text[]
            AND ARRAY(SELECT attr.attname::text FROM unnest(availability_fk.confkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = availability_fk.confrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible availability-studio FK or constraint name collision: %. Stop; never replace it.', availability_fk.conname;
        END IF;
        availability_fk_present := true;
    END LOOP;
    SELECT count(*) INTO availability_null_count FROM public."StudioAvailabilities"
    WHERE "StudioId" IS NULL;
    IF availability_null_count <> 0 THEN
        RAISE EXCEPTION 'StudioAvailabilities NULL StudioId rows: %. Stop; never repair data automatically.', availability_null_count;
    END IF;
    SELECT count(*) INTO availability_orphan_count FROM public."StudioAvailabilities" availability_row
    WHERE availability_row."StudioId" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public."Studios" studio_row WHERE studio_row."Id" = availability_row."StudioId");
    IF availability_orphan_count <> 0 THEN
        RAISE EXCEPTION 'StudioAvailabilities orphan StudioId rows: %. Stop; never repair data automatically.', availability_orphan_count;
    END IF;
    FOR portfolio_fk IN
        SELECT constraint_row.* FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'public."StudioPortfolios"'::regclass
          AND (constraint_row.conname = 'FK_StudioPortfolios_Studios_StudioId'
            OR (constraint_row.contype = 'f' AND (
                constraint_row.confrelid = 'public."Studios"'::regclass
                OR starts_with(constraint_row.conname::text, 'FK_StudioPortfolios_Studios_')
                OR EXISTS (SELECT 1 FROM pg_attribute attr
                    WHERE attr.attrelid = constraint_row.conrelid
                      AND attr.attnum = ANY(constraint_row.conkey) AND attr.attname = 'StudioId'))))
    LOOP
        IF NOT (
            portfolio_fk.contype = 'f' AND portfolio_fk.convalidated
            AND NOT portfolio_fk.condeferrable AND NOT portfolio_fk.condeferred
            AND coalesce((to_jsonb(portfolio_fk)->>'conenforced')::boolean, true)
            AND portfolio_fk.confrelid = 'public."Studios"'::regclass
            AND portfolio_fk.confdeltype = 'c' AND portfolio_fk.confupdtype = 'a'
            AND portfolio_fk.confmatchtype = 's'
            AND ARRAY(SELECT attr.attname::text FROM unnest(portfolio_fk.conkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = portfolio_fk.conrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['StudioId']::text[]
            AND ARRAY(SELECT attr.attname::text FROM unnest(portfolio_fk.confkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = portfolio_fk.confrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible portfolio-studio FK or constraint name collision: %. Stop; never replace it.', portfolio_fk.conname;
        END IF;
        portfolio_fk_present := true;
    END LOOP;
    SELECT count(*) INTO portfolio_null_count FROM public."StudioPortfolios"
    WHERE "StudioId" IS NULL;
    IF portfolio_null_count <> 0 THEN
        RAISE EXCEPTION 'StudioPortfolios NULL StudioId rows: %. Stop; never repair data automatically.', portfolio_null_count;
    END IF;
    SELECT count(*) INTO portfolio_orphan_count FROM public."StudioPortfolios" portfolio_row
    WHERE portfolio_row."StudioId" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public."Studios" studio_row WHERE studio_row."Id" = portfolio_row."StudioId");
    IF portfolio_orphan_count <> 0 THEN
        RAISE EXCEPTION 'StudioPortfolios orphan StudioId rows: %. Stop; never repair data automatically.', portfolio_orphan_count;
    END IF;
    FOR serviceOwner_fk IN
        SELECT constraint_row.* FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'public."StudioServices"'::regclass
          AND (constraint_row.conname = 'FK_StudioServices_Studios_StudioId'
            OR (constraint_row.contype = 'f' AND (
                constraint_row.confrelid = 'public."Studios"'::regclass
                OR starts_with(constraint_row.conname::text, 'FK_StudioServices_Studios_')
                OR EXISTS (SELECT 1 FROM pg_attribute attr
                    WHERE attr.attrelid = constraint_row.conrelid
                      AND attr.attnum = ANY(constraint_row.conkey) AND attr.attname = 'StudioId'))))
    LOOP
        IF NOT (
            serviceOwner_fk.contype = 'f' AND serviceOwner_fk.convalidated
            AND NOT serviceOwner_fk.condeferrable AND NOT serviceOwner_fk.condeferred
            AND coalesce((to_jsonb(serviceOwner_fk)->>'conenforced')::boolean, true)
            AND serviceOwner_fk.confrelid = 'public."Studios"'::regclass
            AND serviceOwner_fk.confdeltype = 'c' AND serviceOwner_fk.confupdtype = 'a'
            AND serviceOwner_fk.confmatchtype = 's'
            AND ARRAY(SELECT attr.attname::text FROM unnest(serviceOwner_fk.conkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = serviceOwner_fk.conrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['StudioId']::text[]
            AND ARRAY(SELECT attr.attname::text FROM unnest(serviceOwner_fk.confkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = serviceOwner_fk.confrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible serviceOwner-studio FK or constraint name collision: %. Stop; never replace it.', serviceOwner_fk.conname;
        END IF;
        serviceOwner_fk_present := true;
    END LOOP;
    SELECT count(*) INTO serviceOwner_null_count FROM public."StudioServices"
    WHERE "StudioId" IS NULL;
    IF serviceOwner_null_count <> 0 THEN
        RAISE EXCEPTION 'StudioServices NULL StudioId rows: %. Stop; never repair data automatically.', serviceOwner_null_count;
    END IF;
    SELECT count(*) INTO serviceOwner_orphan_count FROM public."StudioServices" serviceOwner_row
    WHERE serviceOwner_row."StudioId" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public."Studios" studio_row WHERE studio_row."Id" = serviceOwner_row."StudioId");
    IF serviceOwner_orphan_count <> 0 THEN
        RAISE EXCEPTION 'StudioServices orphan StudioId rows: %. Stop; never repair data automatically.', serviceOwner_orphan_count;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint key_constraint
        JOIN pg_index key_index ON key_index.indexrelid = key_constraint.conindid
        JOIN pg_attribute attr ON attr.attrelid = key_constraint.conrelid
          AND attr.attname = 'Id' AND attr.attnum > 0 AND NOT attr.attisdropped
        WHERE key_constraint.conrelid = 'public."Users"'::regclass
          AND key_constraint.contype IN ('p', 'u')
          AND key_constraint.convalidated AND NOT key_constraint.condeferrable
          AND NOT key_constraint.condeferred
          AND key_constraint.conkey = ARRAY[attr.attnum]::smallint[]
          AND key_index.indrelid = key_constraint.conrelid
          AND key_index.indisunique AND key_index.indisvalid AND key_index.indisready
          AND key_index.indislive AND key_index.indimmediate
          AND key_index.indpred IS NULL AND key_index.indexprs IS NULL
          AND key_index.indnkeyatts = 1 AND key_index.indkey[0] = attr.attnum
    ) THEN
        RAISE EXCEPTION 'Users.Id lacks a valid eligible PK/unique key. Stop and review.';
    END IF;
    FOR ownership_fk IN
        SELECT constraint_row.* FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'public."Studios"'::regclass
          AND (constraint_row.conname = 'FK_Studios_Users_UserId'
            OR (constraint_row.contype = 'f' AND (
                constraint_row.confrelid = 'public."Users"'::regclass
                OR starts_with(constraint_row.conname::text, 'FK_Studios_Users_')
                OR EXISTS (SELECT 1 FROM pg_attribute attr
                    WHERE attr.attrelid = constraint_row.conrelid
                      AND attr.attnum = ANY(constraint_row.conkey) AND attr.attname = 'UserId'))))
    LOOP
        IF NOT (
            ownership_fk.contype = 'f' AND ownership_fk.convalidated
            AND NOT ownership_fk.condeferrable AND NOT ownership_fk.condeferred
            AND coalesce((to_jsonb(ownership_fk)->>'conenforced')::boolean, true)
            AND ownership_fk.confrelid = 'public."Users"'::regclass
            AND ownership_fk.confdeltype = 'c' AND ownership_fk.confupdtype = 'a'
            AND ownership_fk.confmatchtype = 's'
            AND ARRAY(SELECT attr.attname::text FROM unnest(ownership_fk.conkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = ownership_fk.conrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['UserId']::text[]
            AND ARRAY(SELECT attr.attname::text FROM unnest(ownership_fk.confkey) WITH ORDINALITY key_col(num, pos)
                      JOIN pg_attribute attr ON attr.attrelid = ownership_fk.confrelid AND attr.attnum = key_col.num
                      ORDER BY key_col.pos) = ARRAY['Id']::text[]
        ) THEN
            RAISE EXCEPTION 'Incompatible ownership-studio FK or constraint name collision: %. Stop; never replace it.', ownership_fk.conname;
        END IF;
        ownership_fk_present := true;
    END LOOP;
    SELECT count(*) INTO ownership_null_count FROM public."Studios"
    WHERE "UserId" IS NULL;
    IF ownership_null_count <> 0 THEN
        RAISE EXCEPTION 'Studios NULL UserId rows: %. Stop; never repair data automatically.', ownership_null_count;
    END IF;
    SELECT count(*) INTO ownership_orphan_count FROM public."Studios" ownership_row
    WHERE ownership_row."UserId" IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public."Users" studio_row WHERE studio_row."Id" = ownership_row."UserId");
    IF ownership_orphan_count <> 0 THEN
        RAISE EXCEPTION 'Studios orphan UserId rows: %. Stop; never repair data automatically.', ownership_orphan_count;
    END IF;
    SELECT count(*) INTO ownership_duplicate_count FROM (
        SELECT "UserId" FROM public."Studios" WHERE "UserId" IS NOT NULL
        GROUP BY "UserId" HAVING count(*) > 1
    ) duplicate_owners;
    IF ownership_duplicate_count <> 0 THEN
        RAISE EXCEPTION 'Duplicate Studios.UserId groups: %. Stop; never reassign ownership.', ownership_duplicate_count;
    END IF;
    -- Only an exact ordinary unique UserId index is eligible. Do not broaden a
    -- predicate by stripping syntax: accept only the catalog's canonical forms.
    FOR ownership_index IN
        SELECT idx_tbl.oid, idx_tbl.relname, idx.indpred IS NULL AS non_partial,
               pg_get_expr(idx.indpred, idx.indrelid, false) AS predicate_sql,
               coalesce(idx.indrelid = 'public."Studios"'::regclass
                   AND idx_tbl.relkind = 'i' AND idx_tbl.relpersistence = 'p'
                   AND idx.indisunique AND idx.indisvalid AND idx.indisready
                   AND idx.indislive AND idx.indimmediate AND NOT idx.indisprimary
                   AND NOT idx.indisexclusion AND NOT idx.indisreplident
                   AND NOT idx.indisclustered AND NOT idx.indnullsnotdistinct
                   AND method.amname = 'btree' AND idx.indexprs IS NULL
                   AND idx.indnkeyatts = 1 AND idx.indnatts = 1
                   AND idx.indkey[0] = owner_attr.attnum
                   AND idx.indoption[0] = 0 AND idx.indcollation[0] = 0
                   AND opclass.opcdefault AND opclass.opcintype = 'integer'::regtype
                   AND opclass.opcnamespace = 'pg_catalog'::regnamespace,
                   false) AS compatible_base
        FROM pg_class idx_tbl JOIN pg_namespace ns ON ns.oid = idx_tbl.relnamespace
        LEFT JOIN pg_index idx ON idx.indexrelid = idx_tbl.oid
        LEFT JOIN pg_am method ON method.oid = idx_tbl.relam
        LEFT JOIN pg_opclass opclass ON opclass.oid = idx.indclass[0]
        CROSS JOIN pg_attribute owner_attr
        WHERE owner_attr.attrelid = 'public."Studios"'::regclass
          AND owner_attr.attname = 'UserId' AND owner_attr.attnum > 0 AND NOT owner_attr.attisdropped
          AND ((ns.nspname = 'public' AND idx_tbl.relname = 'IX_Studios_UserId')
            OR (idx.indrelid = owner_attr.attrelid AND owner_attr.attnum = ANY(idx.indkey)))
    LOOP
        IF NOT ownership_index.compatible_base THEN
            RAISE EXCEPTION 'Incompatible ownership index or named-object collision: %. Stop; never replace unexpected definitions.', ownership_index.relname;
        END IF;
        IF ownership_index.non_partial THEN
            ownership_index_present := true;
        ELSIF ownership_index.relname = 'IX_Studios_UserId'
          AND ownership_index.predicate_sql IN ('("UserId" IS NOT NULL)', '"UserId" IS NOT NULL') THEN
            -- No constraint/other object may depend on the index being replaced.
            IF EXISTS (SELECT 1 FROM pg_constraint con WHERE con.conindid = ownership_index.oid)
               OR EXISTS (SELECT 1 FROM pg_depend dep
                          WHERE dep.refclassid = 'pg_class'::regclass AND dep.refobjid = ownership_index.oid)
               OR EXISTS (SELECT 1 FROM pg_depend dep
                          WHERE dep.classid = 'pg_class'::regclass AND dep.objid = ownership_index.oid
                            AND dep.deptype IN ('e', 'i')) THEN
                RAISE EXCEPTION 'Ownership partial index has dependencies or extension/internal ownership. Stop; do not drop it.';
            END IF;
            ownership_index_replace := true;
        ELSE
            RAISE EXCEPTION 'Unexpected ownership index predicate/name: %. Stop; never replace it.', ownership_index.relname;
        END IF;
    END LOOP;
    IF NOT ownership_index_present AND NOT ownership_index_replace THEN
        RAISE EXCEPTION 'Expected ownership unique index missing. Creation from absence is not approved.';
    END IF;
    IF ownership_index_replace AND (
        to_regclass('public."IX_Studios_UserId_reconciliation"') IS NOT NULL
        OR EXISTS (SELECT 1 FROM pg_type typ JOIN pg_namespace ns ON ns.oid = typ.typnamespace
                   WHERE ns.nspname = 'public' AND typ.typname IN ('IX_Studios_UserId_reconciliation', 'IX_Studios_UserId'))
    ) THEN
        RAISE EXCEPTION 'Ownership replacement index name/type collision. Stop and review.';
    END IF;
    -- All table/column/key and all seven FK/data checks precede any DDL.
    -- Check the name across public relations, including indexes on other tables.
    FOR service_index IN
        SELECT ic.relname, coalesce(
            i.indrelid = 'public."PhotographyPackageServices"'::regclass
            AND i.indisvalid AND i.indisready AND am.amname = 'btree'
            AND NOT i.indisunique AND i.indexprs IS NULL AND i.indpred IS NULL
            AND i.indnkeyatts = 1
            AND NOT EXISTS (SELECT 1 FROM unnest(i.indoption) opt WHERE opt <> 0)
            AND ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
                      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num
                      WHERE k.pos <= i.indnkeyatts ORDER BY k.pos) = ARRAY['StudioServiceId']::text[],
            false) AS compatible
        FROM pg_class ic JOIN pg_namespace ns ON ns.oid = ic.relnamespace
        LEFT JOIN pg_index i ON i.indexrelid = ic.oid
        LEFT JOIN pg_am am ON am.oid = ic.relam
        WHERE (ns.nspname = 'public' AND ic.relname = 'IX_PhotographyPackageServices_StudioServiceId')
           OR (i.indrelid = 'public."PhotographyPackageServices"'::regclass
               AND i.indnkeyatts = 1
               AND ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, pos)
                         JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num
                         WHERE k.pos <= i.indnkeyatts ORDER BY k.pos) = ARRAY['StudioServiceId']::text[])
    LOOP
        IF NOT service_index.compatible THEN
            RAISE EXCEPTION 'Incompatible StudioServiceId index or relation name collision: %. Stop; never replace it.', service_index.relname;
        END IF;
        service_index_present := true;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace ns ON ns.oid = t.typnamespace
               WHERE ns.nspname = 'public' AND t.typname = 'IX_PhotographyPackageServices_StudioServiceId') THEN
        RAISE EXCEPTION 'StudioServiceId index target type-name collision. Stop and review.';
    END IF;
    IF NOT package_fk_present THEN
        -- All availability guards also completed before this first DDL branch.
        RAISE NOTICE 'Reconciliation required: missing PhotographyPackageServices -> PhotographyPackages FK; orphan count = 0; tables/columns/keys verified.';
        ALTER TABLE public."PhotographyPackageServices" ADD CONSTRAINT "FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~" FOREIGN KEY ("PhotographyPackageId") REFERENCES public."PhotographyPackages" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Package-service FK already compatible; no FK creation required.';
    END IF;
    IF NOT studio_fk_present THEN
        RAISE NOTICE 'Reconciliation required: missing PhotographyPackages -> Studios FK; NULL/orphan counts = 0; columns/key/index verified.';
        ALTER TABLE public."PhotographyPackages" ADD CONSTRAINT "FK_PhotographyPackages_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Package-studio FK already compatible (including equivalent names); no FK creation required.';
    END IF;
    IF NOT service_fk_present THEN
        RAISE NOTICE 'Reconciliation required: missing PhotographyPackageServices -> StudioServices FK; orphan count = 0; tables/columns/keys verified.';
        ALTER TABLE public."PhotographyPackageServices" ADD CONSTRAINT "FK_PhotographyPackageServices_StudioServices_StudioServiceId" FOREIGN KEY ("StudioServiceId") REFERENCES public."StudioServices" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Studio-service FK already compatible; no FK creation required.';
    END IF;
    IF NOT service_index_present THEN
        RAISE NOTICE 'Reconciliation required: missing PhotographyPackageServices StudioServiceId index; table/column/type/key checks passed.';
        CREATE INDEX "IX_PhotographyPackageServices_StudioServiceId" ON public."PhotographyPackageServices" USING btree ("StudioServiceId");
    ELSE
        RAISE NOTICE 'StudioServiceId index already compatible; no index creation required.';
    END IF;
    IF availability_not_null_required THEN
        RAISE NOTICE 'Reconciliation required: StudioAvailabilities.StudioId SET NOT NULL; uuid/non-generated and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioAvailabilities" ALTER COLUMN "StudioId" SET NOT NULL;
    ELSE
        RAISE NOTICE 'StudioAvailabilities.StudioId already NOT NULL; no nullability change required.';
    END IF;
    IF NOT availability_fk_present THEN
        RAISE NOTICE 'Reconciliation required: missing StudioAvailabilities -> Studios FK; eligible key, index and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioAvailabilities" ADD CONSTRAINT "FK_StudioAvailabilities_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Availability-studio FK already compatible (including equivalent names); no FK creation required.';
    END IF;
    IF portfolio_not_null_required THEN
        RAISE NOTICE 'Reconciliation required: StudioPortfolios.StudioId SET NOT NULL; uuid/non-generated and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioPortfolios" ALTER COLUMN "StudioId" SET NOT NULL;
    ELSE
        RAISE NOTICE 'StudioPortfolios.StudioId already NOT NULL; no nullability change required.';
    END IF;
    IF NOT portfolio_fk_present THEN
        RAISE NOTICE 'Reconciliation required: missing StudioPortfolios -> Studios FK; eligible key, index and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioPortfolios" ADD CONSTRAINT "FK_StudioPortfolios_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Portfolio-studio FK already compatible (including equivalent names); no FK creation required.';
    END IF;
    IF serviceOwner_not_null_required THEN
        RAISE NOTICE 'Reconciliation required: StudioServices.StudioId SET NOT NULL; uuid/non-generated and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioServices" ALTER COLUMN "StudioId" SET NOT NULL;
    ELSE
        RAISE NOTICE 'StudioServices.StudioId already NOT NULL; no nullability change required.';
    END IF;
    IF NOT serviceOwner_fk_present THEN
        RAISE NOTICE 'Reconciliation required: missing StudioServices -> Studios FK; eligible key, index and zero NULL/orphan rows verified.';
        ALTER TABLE public."StudioServices" ADD CONSTRAINT "FK_StudioServices_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'ServiceOwner-studio FK already compatible (including equivalent names); no FK creation required.';
    END IF;
    IF ownership_not_null_required THEN
        RAISE NOTICE 'Planned Studios.UserId SET NOT NULL: integer, eligible Users.Id key, zero NULL/orphan/duplicate ownership values verified.';
        ALTER TABLE public."Studios" ALTER COLUMN "UserId" SET NOT NULL;
    END IF;
    IF ownership_index_replace THEN
        RAISE NOTICE 'Planned known partial ownership index replacement: create non-partial unique index first, drop reviewed partial index, rename replacement.';
        CREATE UNIQUE INDEX "IX_Studios_UserId_reconciliation" ON public."Studios" USING btree ("UserId");
        DROP INDEX public."IX_Studios_UserId" RESTRICT;
        ALTER INDEX public."IX_Studios_UserId_reconciliation" RENAME TO "IX_Studios_UserId";
    END IF;
    IF NOT ownership_fk_present THEN
        RAISE NOTICE 'Planned missing Studios -> Users FK; ownership data and structures verified.';
        ALTER TABLE public."Studios" ADD CONSTRAINT "FK_Studios_Users_UserId" FOREIGN KEY ("UserId") REFERENCES public."Users" ("Id") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;
    ELSE
        RAISE NOTICE 'Ownership FK already compatible, including equivalent names; no duplicate creation.';
    END IF;
        IF 'PhoneNumber' = ANY(planned_user_columns) THEN
ALTER TABLE public."Users" ADD "PhoneNumber" character varying(30);

    END IF;
    IF 'ProfilePhotoUrl' = ANY(planned_user_columns) THEN
ALTER TABLE public."Users" ADD "ProfilePhotoUrl" character varying(2048);

    END IF;
    IF 'Bookings' = ANY(planned_tables) THEN
CREATE TABLE public."Bookings" (
    "Id" integer GENERATED BY DEFAULT AS IDENTITY,
    "CustomerId" integer NOT NULL,
    "StudioId" uuid NOT NULL,
    "PackageId" uuid NOT NULL,
    "BookingDate" date NOT NULL,
    "StartTime" time without time zone NOT NULL,
    "EndTime" time without time zone NOT NULL,
    "Location" character varying(500) NOT NULL,
    "Notes" character varying(1000),
    "Status" integer NOT NULL,
    "TotalPrice" numeric(18,2) NOT NULL,
    "PricingSnapshotJson" jsonb,
    "CreatedAt" timestamp with time zone NOT NULL,
    "UpdatedAt" timestamp with time zone,
    CONSTRAINT "PK_Bookings" PRIMARY KEY ("Id"),
    CONSTRAINT "AK_Bookings_Id_CustomerId_StudioId" UNIQUE ("Id", "CustomerId", "StudioId"),
    CONSTRAINT "FK_Bookings_PhotographyPackages_PackageId" FOREIGN KEY ("PackageId") REFERENCES public."PhotographyPackages" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_Bookings_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_Bookings_Users_CustomerId" FOREIGN KEY ("CustomerId") REFERENCES public."Users" ("Id") ON DELETE RESTRICT
);

    END IF;
    IF 'BookingLocations' = ANY(planned_tables) THEN
CREATE TABLE public."BookingLocations" (
    "Id" integer GENERATED BY DEFAULT AS IDENTITY,
    "BookingId" integer NOT NULL,
    "Address" character varying(500) NOT NULL,
    "City" character varying(100) NOT NULL,
    "Latitude" numeric(9,6),
    "Longitude" numeric(9,6),
    "Notes" character varying(1000),
    CONSTRAINT "PK_BookingLocations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_BookingLocations_Bookings_BookingId" FOREIGN KEY ("BookingId") REFERENCES public."Bookings" ("Id") ON DELETE CASCADE
);

    END IF;
    IF 'BookingStatusHistories' = ANY(planned_tables) THEN
CREATE TABLE public."BookingStatusHistories" (
    "Id" integer GENERATED BY DEFAULT AS IDENTITY,
    "BookingId" integer NOT NULL,
    "OldStatus" integer,
    "NewStatus" integer NOT NULL,
    "ChangedBy" character varying(200) NOT NULL,
    "Reason" character varying(1000),
    "CreatedAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_BookingStatusHistories" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_BookingStatusHistories_Bookings_BookingId" FOREIGN KEY ("BookingId") REFERENCES public."Bookings" ("Id") ON DELETE CASCADE
);

    END IF;
    IF 'Notifications' = ANY(planned_tables) THEN
CREATE TABLE public."Notifications" (
    "Id" uuid NOT NULL,
    "CustomerId" integer NOT NULL,
    "Title" character varying(160) NOT NULL,
    "Message" character varying(1000) NOT NULL,
    "Type" character varying(60) NOT NULL,
    "BookingId" integer,
    "IsRead" boolean NOT NULL,
    "CreatedAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_Notifications" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_Notifications_Bookings_BookingId" FOREIGN KEY ("BookingId") REFERENCES public."Bookings" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_Notifications_Users_CustomerId" FOREIGN KEY ("CustomerId") REFERENCES public."Users" ("Id") ON DELETE CASCADE
);

    END IF;
    IF 'Reviews' = ANY(planned_tables) THEN
CREATE TABLE public."Reviews" (
    "Id" uuid NOT NULL,
    "BookingId" integer NOT NULL,
    "CustomerId" integer NOT NULL,
    "StudioId" uuid NOT NULL,
    "Rating" integer NOT NULL,
    "Comment" character varying(2000),
    "CreatedAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_Reviews" PRIMARY KEY ("Id"),
    CONSTRAINT "CK_Reviews_Rating" CHECK ("Rating" BETWEEN 1 AND 5),
    CONSTRAINT "FK_Reviews_Bookings_BookingId_CustomerId_StudioId" FOREIGN KEY ("BookingId", "CustomerId", "StudioId") REFERENCES public."Bookings" ("Id", "CustomerId", "StudioId") ON DELETE RESTRICT,
    CONSTRAINT "FK_Reviews_Studios_StudioId" FOREIGN KEY ("StudioId") REFERENCES public."Studios" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_Reviews_Users_CustomerId" FOREIGN KEY ("CustomerId") REFERENCES public."Users" ("Id") ON DELETE RESTRICT
);

    END IF;
    IF 'BookingLocations' = ANY(planned_tables) THEN
CREATE UNIQUE INDEX "IX_BookingLocations_BookingId" ON public."BookingLocations" ("BookingId");

    END IF;
    IF 'Bookings' = ANY(planned_tables) THEN
CREATE INDEX "IX_Bookings_CustomerId" ON public."Bookings" ("CustomerId");

    END IF;
    IF 'Bookings' = ANY(planned_tables) THEN
CREATE INDEX "IX_Bookings_PackageId" ON public."Bookings" ("PackageId");

    END IF;
    IF 'Bookings' = ANY(planned_tables) THEN
CREATE INDEX "IX_Bookings_StudioId" ON public."Bookings" ("StudioId");

    END IF;
    IF 'BookingStatusHistories' = ANY(planned_tables) THEN
CREATE INDEX "IX_BookingStatusHistories_BookingId" ON public."BookingStatusHistories" ("BookingId");

    END IF;
    IF 'Notifications' = ANY(planned_tables) THEN
CREATE INDEX "IX_Notifications_BookingId" ON public."Notifications" ("BookingId");

    END IF;
    IF 'Notifications' = ANY(planned_tables) THEN
CREATE INDEX "IX_Notifications_CustomerId_CreatedAt" ON public."Notifications" ("CustomerId", "CreatedAt");

    END IF;
    IF 'Notifications' = ANY(planned_tables) THEN
CREATE INDEX "IX_Notifications_CustomerId_IsRead" ON public."Notifications" ("CustomerId", "IsRead");

    END IF;
    IF 'Reviews' = ANY(planned_tables) THEN
CREATE UNIQUE INDEX "IX_Reviews_BookingId" ON public."Reviews" ("BookingId");

    END IF;
    IF 'Reviews' = ANY(planned_tables) THEN
CREATE UNIQUE INDEX "IX_Reviews_BookingId_CustomerId_StudioId" ON public."Reviews" ("BookingId", "CustomerId", "StudioId");

    END IF;
    IF 'Reviews' = ANY(planned_tables) THEN
CREATE INDEX "IX_Reviews_CustomerId" ON public."Reviews" ("CustomerId");

    END IF;
    IF 'Reviews' = ANY(planned_tables) THEN
CREATE INDEX "IX_Reviews_StudioId_CreatedAt" ON public."Reviews" ("StudioId", "CreatedAt");

    END IF;

    RAISE NOTICE 'Preflight passed: absent targets planned, existing targets exactly verified; history unchanged.';
END;
$reconciliation$;

-- No DML, migration-history writes, or destructive rollback.
COMMIT;
