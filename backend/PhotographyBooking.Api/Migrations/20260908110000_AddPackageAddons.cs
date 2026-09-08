using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

public partial class AddPackageAddons : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "PackageAddons",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                PackageId = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                Description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                Price = table.Column<decimal>(type: "numeric(12,2)", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_PackageAddons", x => x.Id);
                table.ForeignKey("FK_PackageAddons_PhotographyPackages_PackageId", x => x.PackageId, "PhotographyPackages", "Id", onDelete: ReferentialAction.Cascade);
            });
        migrationBuilder.CreateIndex(name: "IX_PackageAddons_PackageId", table: "PackageAddons", column: "PackageId");
    }

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.DropTable(name: "PackageAddons");
}