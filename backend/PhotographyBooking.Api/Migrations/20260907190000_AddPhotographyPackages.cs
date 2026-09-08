using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using PhotographyBooking.Api.Data;

#nullable disable
namespace PhotographyBooking.Api.Migrations;

[DbContext(typeof(ApplicationDbContext))]
[Migration("20260907190000_AddPhotographyPackages")]
public class AddPhotographyPackages : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(name: "PhotographyPackages", columns: table => new
        {
            Id = table.Column<Guid>(type: "uuid", nullable: false), StudioId = table.Column<Guid>(type: "uuid", nullable: false),
            PackageName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false), Category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
            Description = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false), Price = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false),
            Duration = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false), NumberOfPhotographers = table.Column<int>(type: "integer", nullable: false),
            CoverImageUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false), Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
            CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false), UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
        }, constraints: table => { table.PrimaryKey("PK_PhotographyPackages", x => x.Id); table.ForeignKey("FK_PhotographyPackages_Studios_StudioId", x => x.StudioId, "Studios", "Id", onDelete: ReferentialAction.Cascade); });
        migrationBuilder.CreateTable(name: "PhotographyPackageServices", columns: table => new { PhotographyPackageId = table.Column<Guid>(type: "uuid", nullable: false), StudioServiceId = table.Column<Guid>(type: "uuid", nullable: false) }, constraints: table => { table.PrimaryKey("PK_PhotographyPackageServices", x => new { x.PhotographyPackageId, x.StudioServiceId }); table.ForeignKey("FK_PhotographyPackageServices_PhotographyPackages_PhotographyPackageId", x => x.PhotographyPackageId, "PhotographyPackages", "Id", onDelete: ReferentialAction.Cascade); table.ForeignKey("FK_PhotographyPackageServices_StudioServices_StudioServiceId", x => x.StudioServiceId, "StudioServices", "Id", onDelete: ReferentialAction.Cascade); });
        migrationBuilder.CreateIndex(name: "IX_PhotographyPackages_StudioId", table: "PhotographyPackages", column: "StudioId");
        migrationBuilder.CreateIndex(name: "IX_PhotographyPackageServices_StudioServiceId", table: "PhotographyPackageServices", column: "StudioServiceId");
    }
    protected override void Down(MigrationBuilder migrationBuilder) { migrationBuilder.DropTable(name: "PhotographyPackageServices"); migrationBuilder.DropTable(name: "PhotographyPackages"); }
}
