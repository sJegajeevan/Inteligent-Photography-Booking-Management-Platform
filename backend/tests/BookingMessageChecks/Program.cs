using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.BookingMessages;
using PhotographyBooking.Api.DTOs.Bookings;
using PhotographyBooking.Api.Models;

var checks = 0;
void Check(bool condition, string name) {
    if (!condition) throw new Exception("FAILED: " + name);
    checks++;
}
// Entirely ephemeral SQLite. Never load application configuration or contact PostgreSQL.
await using var connection = new SqliteConnection("Data Source=:memory:");
await connection.OpenAsync();
await using var db = new MessageTestDb(new DbContextOptionsBuilder<ApplicationDbContext>().UseSqlite(connection).Options);
await db.Database.EnsureCreatedAsync();
db.Users.AddRange(new User { Id = 1, FullName = "Customer One", Role = "Customer", Email = "one@test" },
    new User { Id = 2, FullName = "Studio One", Role = "Studio", Email = "two@test" },
    new User { Id = 3, Role = "Customer", Email = "three@test" },
    new User { Id = 4, Role = "Studio", Email = "four@test" },
    new User { Id = 5, Role = "Admin", Email = "five@test" });
var studio = new Studio { UserId = 2, StudioName = "Studio One", ContactNumber = "+94771234567" };
var otherStudio = new Studio { UserId = 4, StudioName = "Other Studio" };
var package = new PhotographyPackage { Studio = studio, Name = "Portrait" };
var otherPackage = new PhotographyPackage { Studio = otherStudio, Name = "Other" };
db.PhotographyPackages.AddRange(package, otherPackage);
var booking = new Booking { CustomerId = 1, Studio = studio, Package = package, BookingDate = new(2026, 12, 1) };
var otherBooking = new Booking { CustomerId = 3, Studio = otherStudio, Package = otherPackage, BookingDate = new(2026, 12, 2) };
db.Bookings.AddRange(booking, otherBooking);
await db.SaveChangesAsync();
db.ChangeTracker.Clear();
var now = new DateTimeOffset(2026, 9, 28, 10, 0, 0, TimeSpan.Zero);
var clock = new MessageClock(now);
// Test JWTs are signed with an ephemeral random key; exercise real auth middleware.
var key = new SymmetricSecurityKey(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [] });
builder.Logging.ClearProviders();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options => {
    options.TokenValidationParameters = new TokenValidationParameters {
        ValidateIssuer = false, ValidateAudience = false, ValidateIssuerSigningKey = true,
        IssuerSigningKey = key, ValidateLifetime = true
    };
});
builder.Services.AddAuthorization();
builder.Services.AddControllers().AddApplicationPart(typeof(BookingsController).Assembly).AddControllersAsServices();
builder.Services.AddTransient(_ => new BookingsController(db, null!, null!, null!, clock));
await using var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Urls.Add("http://127.0.0.1:0");
await app.StartAsync();
using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
void Actor(int id, string role) {
    var token = new JwtSecurityToken(claims: [new Claim(ClaimTypes.NameIdentifier, id.ToString()), new Claim(ClaimTypes.Role, role)],
        expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
}
var path = $"/api/bookings/{booking.Id}/messages";
Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.Unauthorized, "anonymous read rejected");
Check((await client.PostAsJsonAsync(path, new { message = "hello" })).StatusCode == HttpStatusCode.Unauthorized, "anonymous send rejected");
Actor(1, "Customer");
var details = (await client.GetFromJsonAsync<BookingResponse>($"/api/bookings/{booking.Id}"))!;
Check(details.StudioContactNumber == studio.ContactNumber, "owned booking exposes booked studio contact");
Actor(3, "Customer");
Check((await client.GetAsync($"/api/bookings/{booking.Id}")).StatusCode == HttpStatusCode.NotFound, "other customer cannot read booking contact");
Actor(4, "Studio");
Check((await client.GetAsync($"/api/bookings/{booking.Id}")).StatusCode == HttpStatusCode.NotFound, "other studio cannot read booking contact");
Actor(1, "Customer");
Check((await client.GetFromJsonAsync<List<BookingMessageResponse>>(path))!.Count == 0, "own empty conversation readable");
var response = await client.PostAsJsonAsync(path, new { message = "  Hello studio  ", senderUserId = 4, senderRole = "Studio", bookingId = otherBooking.Id, sentAt = "2000-01-01T00:00:00Z" });
Check(response.StatusCode == HttpStatusCode.Created, "customer can send");
var created = (await response.Content.ReadFromJsonAsync<BookingMessageResponse>())!;
Check(created.SenderUserId == 1 && created.SenderRole == "Customer" && created.SenderName == "Customer One", "sender derived from JWT and database");
Check(created.BookingId == booking.Id && created.Message == "Hello studio" && created.SentAt == now.UtcDateTime && created.SentAt.Kind == DateTimeKind.Utc, "route, trim and UTC server clock used");
Check(!await db.BookingMessages.AnyAsync(m => m.BookingId == otherBooking.Id), "spoofed booking ignored");
foreach (var text in new string?[] { null, "", " \t\n", new('x', 1001) })
    Check((await client.PostAsJsonAsync(path, new { message = text })).StatusCode == HttpStatusCode.BadRequest, "invalid text rejected");
Check((await client.PostAsJsonAsync(path, new { message = new string('x', 1000) })).StatusCode == HttpStatusCode.Created, "1000 character boundary accepted");
Check((await client.GetAsync("/api/bookings/999999/messages")).StatusCode == HttpStatusCode.NotFound, "unknown read safe");
Check((await client.PostAsJsonAsync("/api/bookings/999999/messages", new { message = "hello" })).StatusCode == HttpStatusCode.NotFound, "unknown send safe");
Check((await client.GetAsync("/api/bookings/conversations")).StatusCode == HttpStatusCode.Forbidden, "customer cannot list studio conversations");
foreach (var (id, role) in new[] { (3, "Customer"), (4, "Studio") }) {
    Actor(id, role);
    Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.NotFound, role + " cross-owner read denied");
    Check((await client.PostAsJsonAsync(path, new { message = "intrusion" })).StatusCode == HttpStatusCode.NotFound, role + " cross-owner write denied");
}
Actor(2, "Studio");
Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.OK, "owner studio can read");
clock.Now = now.AddMinutes(1);
Check((await client.PostAsJsonAsync(path, new { message = "Studio reply" })).StatusCode == HttpStatusCode.Created, "owner studio can reply");
// Insert an older row last, verifying chronological order rather than insertion order.
db.BookingMessages.Add(new BookingMessage { BookingId = booking.Id, SenderUserId = 1, Message = "Earlier", SentAt = now.AddMinutes(-1).UtcDateTime });
await db.SaveChangesAsync();
var messages = (await client.GetFromJsonAsync<List<BookingMessageResponse>>(path))!;
Check(messages.First().Message == "Earlier" && messages.Last().Message == "Studio reply", "chronological order");
Check(messages.Select(m => m.Id).SequenceEqual(messages.OrderBy(m => m.SentAt).ThenBy(m => m.Id).Select(m => m.Id)), "stable timestamp tie ordering");
Check(messages.Last().SenderRole == "Studio" && messages.Last().SenderUserId == 2, "studio identity derived");
var conversations = (await client.GetFromJsonAsync<List<BookingConversationResponse>>("/api/bookings/conversations"))!;
Check(conversations.Count == 1 && conversations[0].BookingId == booking.Id && conversations[0].LatestMessage == "Studio reply", "list scoped to studio with latest preview");
Actor(4, "Studio");
conversations = (await client.GetFromJsonAsync<List<BookingConversationResponse>>("/api/bookings/conversations"))!;
Check(conversations.Count == 1 && conversations[0].BookingId == otherBooking.Id && conversations[0].LatestMessage == null, "other studio sees only its own empty booking");
Actor(1, "Studio");
Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.Forbidden, "JWT database role mismatch denied");
Actor(5, "Admin");
Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.Forbidden, "admin not a conversation participant");
Actor(1, "Customer");
Check((await client.GetFromJsonAsync<List<BookingMessageResponse>>(path))!.Count == 4, "customer reads reply and denied sends wrote nothing");
await app.StopAsync();
Console.WriteLine($"Passed {checks} booking messaging checks (HTTP/JWT + ephemeral SQLite). No application database accessed.");

sealed class MessageClock(DateTimeOffset now) : TimeProvider {
    public DateTimeOffset Now { get; set; } = now;
    public override DateTimeOffset GetUtcNow() => Now;
}
sealed class MessageTestDb(DbContextOptions<ApplicationDbContext> options) : ApplicationDbContext(options) {
    protected override void OnModelCreating(ModelBuilder builder) {
        base.OnModelCreating(builder);
        Type[] included = [typeof(User), typeof(Studio), typeof(PhotographyPackage), typeof(Booking), typeof(BookingMessage)];
        foreach (var entity in builder.Model.GetEntityTypes().ToList())
            if (!included.Contains(entity.ClrType)) builder.Ignore(entity.ClrType);
    }
}
