using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Bookings;
using PhotographyBooking.Api.DTOs.Reviews;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

var count = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception("FAILED: " + name);
    count++;
}
var day = new DateOnly(2026, 12, 1);
// 13:00 Colombo is 07:30 UTC, independent of the host timezone.
var endUtc = new DateTimeOffset(2026, 12, 1, 7, 30, 0, TimeSpan.Zero);
Check(!BookingCompletionRules.HasShootEnded(day, new(13, 0), endUtc), "exact end has not yet passed");
Check(BookingCompletionRules.HasShootEnded(day, new(13, 0), endUtc.AddTicks(1)), "one tick after end");
Check(BookingCompletionRules.HasShootEnded(day, new(13, 0), endUtc.AddSeconds(1).ToOffset(TimeSpan.FromHours(-5))), "offset independent");
Check(!BookingCompletionRules.HasShootEnded(day, new(0, 15), new(2026, 11, 30, 18, 44, 0, TimeSpan.Zero)), "local date differs from UTC date");

await using var connection = new SqliteConnection("Data Source=:memory:");
await connection.OpenAsync();
await using var db = new TestDb(new DbContextOptionsBuilder<ApplicationDbContext>().UseSqlite(connection).Options);
await db.Database.EnsureCreatedAsync();
db.Users.AddRange(
    new User { Id = 1, Role = "Customer", Email = "customer@test" },
    new User { Id = 2, Role = "Studio", Email = "studio@test" },
    new User { Id = 3, Role = "Studio", Email = "other-studio@test" },
    new User { Id = 4, Role = "Customer", Email = "other-customer@test" });
var studio = new Studio { UserId = 2, StudioName = "Test studio" };
var package = new PhotographyPackage { Studio = studio, Name = "Test package" };
db.PhotographyPackages.Add(package);
await db.SaveChangesAsync();
var clock = new Clock { Now = endUtc };
ControllerContext Actor(int id, string role) => new()
{
    HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([
        new Claim(ClaimTypes.NameIdentifier, id.ToString()), new Claim(ClaimTypes.Role, role)
    ], "test")) }
};
BookingsController Bookings(int id = 2, string role = "Studio") => new(db, null!, null!, null!, clock)
{ ControllerContext = Actor(id, role) };
ReviewsController Reviews(int id = 1) => new(db, clock) { ControllerContext = Actor(id, "Customer") };
async Task<Booking> Seed(BookingStatus status)
{
    var booking = new Booking { CustomerId = 1, StudioId = studio.Id, PackageId = package.Id,
        BookingDate = day, StartTime = new(9, 0), EndTime = new(13, 0), Status = status, TotalPrice = 80000 };
    db.Bookings.Add(booking);
    await db.SaveChangesAsync();
    db.ChangeTracker.Clear();
    return booking;
}
foreach (var (now, label) in new[] {
    (endUtc.AddDays(-1), "future shoot"), (endUtc.AddHours(-1), "in progress"), (endUtc, "exact end") })
{
    clock.Now = now;
    var booking = await Seed(BookingStatus.Confirmed);
    var result = await Bookings().UpdateBookingStatus(booking.Id, new() { NewStatus = BookingStatus.Completed });
    Check(result.Result is BadRequestObjectResult, label + " completion rejected");
    Check((await db.Bookings.AsNoTracking().SingleAsync(b => b.Id == booking.Id)).Status == BookingStatus.Confirmed, label + " status unchanged");
    Check(!await db.BookingStatusHistories.AnyAsync(h => h.BookingId == booking.Id) &&
        !await db.Notifications.AnyAsync(n => n.BookingId == booking.Id), label + " no history or notification writes");
    var legacy = await Seed(BookingStatus.Completed);
    var review = await Reviews().Create(new() { BookingId = legacy.Id, Rating = 5 }, default);
    Check(review.Result is BadRequestObjectResult, label + " legacy completed review rejected");
    Check(!await db.Reviews.AnyAsync(r => r.BookingId == legacy.Id), label + " no review saved");
}
clock.Now = endUtc.AddSeconds(1);
var past = await Seed(BookingStatus.Confirmed);
Check((await Bookings(3).UpdateBookingStatus(past.Id, new() { NewStatus = BookingStatus.Completed })).Result is NotFoundObjectResult,
    "other studio cannot complete");
Check((await Bookings(1, "Customer").UpdateBookingStatus(past.Id, new() { NewStatus = BookingStatus.Completed })).Result is ForbidResult,
    "customer cannot complete");
Check((await Bookings().UpdateBookingStatus(past.Id, new() { NewStatus = BookingStatus.Completed })).Result is OkObjectResult,
    "past confirmed completion succeeds");
Check((await db.Bookings.AsNoTracking().SingleAsync(b => b.Id == past.Id)).Status == BookingStatus.Completed, "completion persisted");
var history = await db.BookingStatusHistories.SingleAsync(h => h.BookingId == past.Id);
Check(history.OldStatus == BookingStatus.Confirmed && history.NewStatus == BookingStatus.Completed && history.ChangedBy == "Studio #2", "history preserved");
Check(await db.Notifications.CountAsync(n => n.BookingId == past.Id) == 1, "notification preserved");
Check((await Reviews(4).Create(new() { BookingId = past.Id, Rating = 5 }, default)).Result is NotFoundObjectResult, "other customer cannot review");
Check((await Reviews().Create(new() { BookingId = past.Id, Rating = 5 }, default)).Result is ObjectResult { StatusCode: 201 }, "ended completed review succeeds");
Check((await Reviews().Create(new() { BookingId = past.Id, Rating = 5 }, default)).Result is ConflictObjectResult, "duplicate review rejected");
foreach (var status in Enum.GetValues<BookingStatus>().Where(s => s != BookingStatus.Confirmed))
{
    var booking = await Seed(status);
    Check((await Bookings().UpdateBookingStatus(booking.Id, new() { NewStatus = BookingStatus.Completed })).Result is BadRequestObjectResult,
        status + " cannot transition to completed");
}
var confirmed = await Seed(BookingStatus.Confirmed);
Check((await Reviews().Create(new() { BookingId = confirmed.Id, Rating = 5 }, default)).Result is BadRequestObjectResult,
    "ended confirmed booking still cannot be reviewed");
clock.Now = endUtc.AddDays(-1);
Check((await Bookings().UpdateBookingStatus(confirmed.Id, new() { NewStatus = BookingStatus.Rescheduled })).Result is OkObjectResult,
    "future rescheduling unaffected");
Check((await Bookings(1, "Customer").CancelBooking(confirmed.Id, new())).Result is OkObjectResult, "customer cancellation unaffected");
Check(typeof(BookingsController).GetMethod(nameof(BookingsController.UpdateBookingStatus))!
    .GetCustomAttributes(typeof(AuthorizeAttribute), true).Cast<AuthorizeAttribute>().Single().Roles == "Studio", "studio endpoint restriction preserved");
Check(typeof(ReviewsController).GetMethod(nameof(ReviewsController.Create))!
    .GetCustomAttributes(typeof(AuthorizeAttribute), true).Cast<AuthorizeAttribute>().Single().Roles == "Customer", "customer review restriction preserved");
Console.WriteLine($"Passed {count} booking completion checks. Ephemeral SQLite only; no application database accessed.");

sealed class Clock : TimeProvider
{
    public DateTimeOffset Now { get; set; }
    public override DateTimeOffset GetUtcNow() => Now;
}

// Retain real booking relationships and constraints; exclude unrelated PostgreSQL-only
// models from the isolated SQLite test database. Production configuration is unchanged.
sealed class TestDb(DbContextOptions<ApplicationDbContext> options) : ApplicationDbContext(options)
{
    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        Type[] included = [typeof(User), typeof(Studio), typeof(PhotographyPackage), typeof(Booking),
            typeof(Review), typeof(BookingStatusHistory), typeof(Notification)];
        foreach (var entity in builder.Model.GetEntityTypes().ToList())
            if (!included.Contains(entity.ClrType)) builder.Ignore(entity.ClrType);
    }
}
