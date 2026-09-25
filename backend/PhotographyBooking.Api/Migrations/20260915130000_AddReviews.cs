using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using PhotographyBooking.Api.Data;

#nullable disable

namespace PhotographyBooking.Api.Migrations;

[DbContext(typeof(ApplicationDbContext))]
[Migration("20260915130000_AddReviews")]
public partial class AddReviews : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddUniqueConstraint(
            "AK_Bookings_Id_CustomerId_StudioId", "Bookings", new[] { "Id", "CustomerId", "StudioId" });

        migrationBuilder.CreateTable(
            name: "Reviews",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                BookingId = table.Column<int>(type: "integer", nullable: false),
                CustomerId = table.Column<int>(type: "integer", nullable: false),
                StudioId = table.Column<Guid>(type: "uuid", nullable: false),
                Rating = table.Column<int>(type: "integer", nullable: false),
                Comment = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Reviews", review => review.Id);
                table.CheckConstraint("CK_Reviews_Rating", "\"Rating\" BETWEEN 1 AND 5");
                table.ForeignKey(
                    "FK_Reviews_Bookings_BookingId_CustomerId_StudioId",
                    review => new { review.BookingId, review.CustomerId, review.StudioId },
                    "Bookings", new[] { "Id", "CustomerId", "StudioId" },
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey("FK_Reviews_Users_CustomerId", review => review.CustomerId,
                    "Users", "Id", onDelete: ReferentialAction.Restrict);
                table.ForeignKey("FK_Reviews_Studios_StudioId", review => review.StudioId,
                    "Studios", "Id", onDelete: ReferentialAction.Restrict);
            });

        migrationBuilder.CreateIndex("IX_Reviews_BookingId", "Reviews", "BookingId", unique: true);
        migrationBuilder.CreateIndex("IX_Reviews_BookingId_CustomerId_StudioId", "Reviews",
            new[] { "BookingId", "CustomerId", "StudioId" }, unique: true);
        migrationBuilder.CreateIndex("IX_Reviews_CustomerId", "Reviews", "CustomerId");
        migrationBuilder.CreateIndex("IX_Reviews_StudioId_CreatedAt", "Reviews", new[] { "StudioId", "CreatedAt" });
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable("Reviews");
        migrationBuilder.DropUniqueConstraint("AK_Bookings_Id_CustomerId_StudioId", "Bookings");
    }
}
