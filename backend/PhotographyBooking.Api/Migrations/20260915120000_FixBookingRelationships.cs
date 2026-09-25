using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using PhotographyBooking.Api.Data;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

[DbContext(typeof(ApplicationDbContext))]
[Migration("20260915120000_FixBookingRelationships")]
public partial class FixBookingRelationships : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Legacy integer IDs have no reliable mapping to studio/package UUIDs.
        // The confirmed deployment prerequisite is an empty Bookings table.
        // Lock before checking so a concurrent insert cannot invalidate it.
        migrationBuilder.Sql("""
            LOCK TABLE "Bookings" IN ACCESS EXCLUSIVE MODE;
            DO $$
            BEGIN
                IF EXISTS (SELECT 1 FROM "Bookings") THEN
                    RAISE EXCEPTION 'FixBookingRelationships requires an empty Bookings table. Existing bookings need a verified integer-to-UUID mapping; no rows have been removed.';
                END IF;
            END $$;
            ALTER TABLE "Bookings"
                ALTER COLUMN "StudioId" TYPE uuid USING NULL::uuid,
                ALTER COLUMN "PackageId" TYPE uuid USING NULL::uuid;
            """);

        migrationBuilder.CreateIndex("IX_Bookings_CustomerId", "Bookings", "CustomerId");
        migrationBuilder.CreateIndex("IX_Bookings_StudioId", "Bookings", "StudioId");
        migrationBuilder.CreateIndex("IX_Bookings_PackageId", "Bookings", "PackageId");

        migrationBuilder.AddForeignKey(
            "FK_Bookings_Users_CustomerId", "Bookings", "CustomerId", "Users",
            principalColumn: "Id", onDelete: ReferentialAction.Restrict);
        migrationBuilder.AddForeignKey(
            "FK_Bookings_Studios_StudioId", "Bookings", "StudioId", "Studios",
            principalColumn: "Id", onDelete: ReferentialAction.Restrict);
        migrationBuilder.AddForeignKey(
            "FK_Bookings_PhotographyPackages_PackageId", "Bookings", "PackageId", "PhotographyPackages",
            principalColumn: "Id", onDelete: ReferentialAction.Restrict);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            LOCK TABLE "Bookings" IN ACCESS EXCLUSIVE MODE;
            DO $$
            BEGIN
                IF EXISTS (SELECT 1 FROM "Bookings") THEN
                    RAISE EXCEPTION 'Cannot revert booking UUIDs to integers while bookings exist. No rows have been removed.';
                END IF;
            END $$;
            """);

        migrationBuilder.DropForeignKey("FK_Bookings_Users_CustomerId", "Bookings");
        migrationBuilder.DropForeignKey("FK_Bookings_Studios_StudioId", "Bookings");
        migrationBuilder.DropForeignKey("FK_Bookings_PhotographyPackages_PackageId", "Bookings");
        migrationBuilder.DropIndex("IX_Bookings_CustomerId", "Bookings");
        migrationBuilder.DropIndex("IX_Bookings_StudioId", "Bookings");
        migrationBuilder.DropIndex("IX_Bookings_PackageId", "Bookings");

        migrationBuilder.Sql("""
            ALTER TABLE "Bookings"
                ALTER COLUMN "StudioId" TYPE integer USING NULL::integer,
                ALTER COLUMN "PackageId" TYPE integer USING NULL::integer;
            """);
    }
}
