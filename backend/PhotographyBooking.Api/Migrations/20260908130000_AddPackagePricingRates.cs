using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

public partial class AddPackagePricingRates : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<decimal>("ExtraHourRate", "PhotographyPackages", type: "numeric(12,2)", nullable: false, defaultValue: 0m);
        migrationBuilder.AddColumn<decimal>("AdditionalPhotographerRate", "PhotographyPackages", type: "numeric(12,2)", nullable: false, defaultValue: 0m);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn("ExtraHourRate", "PhotographyPackages");
        migrationBuilder.DropColumn("AdditionalPhotographerRate", "PhotographyPackages");
    }
}