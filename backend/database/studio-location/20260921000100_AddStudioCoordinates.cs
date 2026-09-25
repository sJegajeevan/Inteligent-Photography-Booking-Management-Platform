using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using PhotographyBooking.Api.Data;

namespace PhotographyBooking.Api.LocationMigrationReview;

// Review-only migration. Compiled by the offline preparation tool, NOT the API.
// Do not append this to the archived, inconsistent migration chain.
[DbContext(typeof(ApplicationDbContext))]
[Migration("20260921000100_AddStudioCoordinates")]
public sealed class AddStudioCoordinates : Migration
{
    public const string CoordinateConstraint =
        "(\"Latitude\" IS NULL AND \"Longitude\" IS NULL) OR " +
        "(\"Latitude\" IS NOT NULL AND \"Longitude\" IS NOT NULL AND " +
        "\"Latitude\" BETWEEN -90 AND 90 AND \"Longitude\" BETWEEN -180 AND 180)";

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>(
            name: "Latitude", schema: "public", table: "Studios",
            type: "numeric(9,6)", precision: 9, scale: 6, nullable: true);
        migrationBuilder.AddColumn<decimal>(
            name: "Longitude", schema: "public", table: "Studios",
            type: "numeric(9,6)", precision: 9, scale: 6, nullable: true);
        migrationBuilder.AddCheckConstraint(
            name: "CK_Studios_Coordinates", schema: "public", table: "Studios",
            sql: CoordinateConstraint);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Review only: rollback would discard coordinates entered after deployment.
        migrationBuilder.DropCheckConstraint("CK_Studios_Coordinates", "Studios", "public");
        migrationBuilder.DropColumn("Latitude", "Studios", "public");
        migrationBuilder.DropColumn("Longitude", "Studios", "public");
    }
}
