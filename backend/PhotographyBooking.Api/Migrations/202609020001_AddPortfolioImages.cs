using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using PhotographyBooking.Api.Data;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

[DbContext(typeof(ApplicationDbContext))]
[Migration("202609020001_AddPortfolioImages")]
public class AddPortfolioImages : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "StudioPortfolioImages",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                StudioPortfolioId = table.Column<Guid>(type: "uuid", nullable: false),
                ImageUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                DisplayOrder = table.Column<int>(type: "integer", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_StudioPortfolioImages", x => x.Id);
                table.ForeignKey("FK_StudioPortfolioImages_StudioPortfolios_StudioPortfolioId", x => x.StudioPortfolioId, "StudioPortfolios", "Id", onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(name: "IX_StudioPortfolioImages_StudioPortfolioId_DisplayOrder", table: "StudioPortfolioImages", columns: new[] { "StudioPortfolioId", "DisplayOrder" });
        migrationBuilder.Sql("""
            INSERT INTO "StudioPortfolioImages" ("Id", "StudioPortfolioId", "ImageUrl", "DisplayOrder", "CreatedAt")
            SELECT "Id", "Id", "ImageUrl", 0, "CreatedAt"
            FROM "StudioPortfolios"
            WHERE "ImageUrl" <> '';
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.DropTable(name: "StudioPortfolioImages");
}
