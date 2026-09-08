using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

public partial class AddPackageManagementFields : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>("Name", "PhotographyPackages", maxLength: 160, nullable: false, defaultValue: "");
        migrationBuilder.AddColumn<decimal>("BasePrice", "PhotographyPackages", type: "numeric(12,2)", nullable: false, defaultValue: 0m);
        migrationBuilder.AddColumn<decimal>("DurationHours", "PhotographyPackages", type: "numeric(5,2)", nullable: false, defaultValue: 0m);
        migrationBuilder.AddColumn<int>("EditedPhotoCount", "PhotographyPackages", nullable: false, defaultValue: 0);
        migrationBuilder.AddColumn<bool>("AlbumIncluded", "PhotographyPackages", nullable: false, defaultValue: false);
        migrationBuilder.AddColumn<bool>("VideoIncluded", "PhotographyPackages", nullable: false, defaultValue: false);
        migrationBuilder.Sql("UPDATE \"PhotographyPackages\" SET \"Name\" = \"PackageName\" WHERE \"Name\" = '' AND \"PackageName\" <> ''; UPDATE \"PhotographyPackages\" SET \"BasePrice\" = \"Price\" WHERE \"BasePrice\" = 0 AND \"Price\" <> 0;");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn("Name", "PhotographyPackages");
        migrationBuilder.DropColumn("BasePrice", "PhotographyPackages");
        migrationBuilder.DropColumn("DurationHours", "PhotographyPackages");
        migrationBuilder.DropColumn("EditedPhotoCount", "PhotographyPackages");
        migrationBuilder.DropColumn("AlbumIncluded", "PhotographyPackages");
        migrationBuilder.DropColumn("VideoIncluded", "PhotographyPackages");
    }
}