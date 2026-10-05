using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Admin;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

var checks = 0;
void Check(bool condition, string name) {
    if (!condition) throw new Exception("FAILED Admin: " + name);
    checks++;
}
// Isolated in-memory SQLite; never start the application or load its configuration.
await using var connection = new SqliteConnection("Data Source=:memory:");
await connection.OpenAsync();
await using var db = new AdminTestDb(new DbContextOptionsBuilder<ApplicationDbContext>().UseSqlite(connection).Options);
await db.Database.EnsureCreatedAsync();
db.Users.AddRange(new User { Id = 1, FullName = "Customer One", Role = "Customer", Email = "one@test" },
    new User { Id = 2, FullName = "Studio Owner", Role = "Studio", Email = "two@test" },
    new User { Id = 3, FullName = "Other Customer", Role = "Customer", Email = "three@test" },
    new User { Id = 4, FullName = "Other Owner", Role = "Studio", Email = "four@test" },
    new User { Id = 5, FullName = "Admin", Role = "Admin", Email = "five@test" });
var studio = new Studio { UserId = 2, StudioName = "Same Studio", Location = "Colombo" };
var other = new Studio { UserId = 4, StudioName = "Same Studio", Location = "Galle" };
var package = new PhotographyPackage { Studio = studio, Name = "Wedding", Price = 5000 };
var otherPackage = new PhotographyPackage { Studio = other, Name = "Wedding", Price = 5000 };
db.PhotographyPackages.AddRange(package, otherPackage);
for (var i = 1; i <= 25; i++) db.Bookings.Add(new Booking {
    Id = i, CustomerId = i <= 20 ? 1 : 3, Studio = i <= 20 ? studio : other,
    Package = i <= 20 ? package : otherPackage, BookingDate = new(2026, 10, i <= 15 ? 15 : 20),
    StartTime = new(10, 0), EndTime = new(12, 0), TotalPrice = 5000,
    Status = i <= 15 ? BookingStatus.Pending : BookingStatus.Confirmed,
    PricingSnapshotJson = "{\"BasePrice\":5000,\"FinalPrice\":5000}", Notes = "Outdoor shoot"
});
db.Reviews.Add(new Review { BookingId = 25, CustomerId = 3, Studio = other, Rating = 5, Comment = "Great" });
await db.SaveChangesAsync();
db.ChangeTracker.Clear();

var key = new SymmetricSecurityKey(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [], EnvironmentName = "Production" });
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Error);
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
    options.TokenValidationParameters = new TokenValidationParameters {
        ValidateIssuer = false, ValidateAudience = false, ValidateIssuerSigningKey = true,
        IssuerSigningKey = key, ValidateLifetime = true
    });
builder.Services.AddDataProtection().UseEphemeralDataProtectionProvider();
        builder.Services.Configure<Microsoft.AspNetCore.DataProtection.KeyManagement.KeyManagementOptions>(options => {
            options.XmlRepository = new AdminXmlRepository(); options.XmlEncryptor = null;
        });
builder.Services.AddAuthorization();
builder.Services.AddControllers().AddApplicationPart(typeof(AdminController).Assembly).AddControllersAsServices();
builder.Services.AddTransient(_ => new AdminController(db));
await using var app = builder.Build();
app.UseAuthentication(); app.UseAuthorization(); app.MapControllers();
app.Urls.Add("http://127.0.0.1:0");
await app.StartAsync();
using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
void Actor(int id, string role) {
    var token = new JwtSecurityToken(claims: [new Claim(ClaimTypes.NameIdentifier, id.ToString()), new Claim(ClaimTypes.Role, role)],
        expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
}
string[] routes = ["dashboard", "studios", $"studios/{studio.Id}", "customers", "customers/1", "bookings", "bookings/1", "reviews", "reports"];
foreach (var route in routes) Check((await client.GetAsync("/api/admin/" + route)).StatusCode == HttpStatusCode.Unauthorized, "anonymous 401 " + route);
foreach (var (id, role) in new[] { (1, "Customer"), (2, "Studio") }) {
    Actor(id, role);
    foreach (var route in routes) Check((await client.GetAsync("/api/admin/" + route)).StatusCode == HttpStatusCode.Forbidden, role + " 403 " + route);
}
Actor(5, "Admin");
foreach (var route in routes) {
    var response = await client.GetAsync("/api/admin/" + route);
    Check(response.StatusCode == HttpStatusCode.OK, "Admin 200 " + route + " " + await response.Content.ReadAsStringAsync());
}
async Task<AdminPage<AdminBookingSummary>> Bookings(string query) =>
    (await client.GetFromJsonAsync<AdminPage<AdminBookingSummary>>("/api/admin/bookings" + query))!;
var first = await Bookings("?page=1&pageSize=10");
var second = await Bookings("?page=2&pageSize=10");
Check(first.TotalCount == 25 && first.TotalPages == 3 && first.Items.Count == 10, "bounded page with totals");
Check(first.Items.Select(b => b.Id).SequenceEqual(Enumerable.Range(16, 10).Reverse()), "date then ID descending");
Check(!first.Items.Select(b => b.Id).Intersect(second.Items.Select(b => b.Id)).Any(), "disjoint stable pages");
Check((await Bookings("?search=customer%20one")).TotalCount == 20, "customer search");
Check((await Bookings("?search=Wedding")).TotalCount == 25, "package search");
Check((await Bookings("?search=Same%20Studio")).TotalCount == 25, "studio search");
Check((await Bookings("?search=25")).Items.Single().Id == 25, "booking ID search");
Check((await Bookings("?status=Pending")).TotalCount == 15, "status filter");
Check((await Bookings($"?studioId={other.Id}")).TotalCount == 5, "studio filter");
Check((await Bookings("?customerId=3")).TotalCount == 5, "customer ID filter");
Check((await Bookings("?fromDate=2026-10-20&toDate=2026-10-20")).TotalCount == 10, "inclusive booking date range");
Check((await Bookings($"?studioId={studio.Id}&status=Confirmed&customerId=1&fromDate=2026-10-20&toDate=2026-10-20")).TotalCount == 5, "combined filters");
Check((await Bookings("?search=absent")).TotalCount == 0 && (await Bookings("?search=absent")).Items.Count == 0, "empty results");
Check((await Bookings("?page=4")).Items.Count == 0, "out of range page bounded");
foreach (var query in new[] { "page=0", "page=10001", "pageSize=9", "pageSize=101", "status=999", "status=Unknown", "studioId=bad", "studioId=00000000-0000-0000-0000-000000000000", "customerId=0", "fromDate=bad", "fromDate=2026-10-20&toDate=2026-10-01", "search=" + new string('x', 201) })
    Check((await client.GetAsync("/api/admin/bookings?" + query)).StatusCode == HttpStatusCode.BadRequest, "invalid filter " + query.Split('=')[0]);
foreach (var route in new[] { "studios", "customers", "reviews" }) {
    var response = await client.GetAsync($"/api/admin/{route}?pageSize=101");
    Check(response.StatusCode == HttpStatusCode.BadRequest, "bounded " + route);
}
Check((await client.GetFromJsonAsync<AdminPage<AdminStudioSummary>>("/api/admin/studios?search=Galle"))!.Items.Single().Id == other.Id, "studio search");
Check((await client.GetFromJsonAsync<AdminPage<AdminCustomerSummary>>("/api/admin/customers?search=Other"))!.Items.Single().Id == 3, "customer collection search");
Check((await client.GetFromJsonAsync<AdminPage<AdminReviewSummary>>("/api/admin/reviews?rating=4"))!.TotalCount == 0, "review rating");
Check((await client.GetFromJsonAsync<AdminPage<AdminReviewSummary>>("/api/admin/reviews?search=Great&rating=5"))!.TotalCount == 1, "review combined filters");
Check((await client.GetAsync("/api/admin/reviews?rating=6")).StatusCode == HttpStatusCode.BadRequest, "invalid rating");
foreach (var route in new[] { $"studios/{Guid.NewGuid()}", "customers/999", "bookings/999" })
    Check((await client.GetAsync("/api/admin/" + route)).StatusCode == HttpStatusCode.NotFound, "missing detail 404");
var reports = (await client.GetFromJsonAsync<AdminReportsResponse>("/api/admin/reports"))!;
Check(reports.BookingsByStudio.Count == 2 && reports.PopularPackages.Count == 2, "duplicate names retain distinct IDs");
Check((await client.GetFromJsonAsync<AdminStudioDetail>($"/api/admin/studios/{other.Id}"))!.ReviewCount == 1, "studio review count");
var dashboard = (await client.GetFromJsonAsync<AdminDashboardResponse>("/api/admin/dashboard"))!;
Check(dashboard.TotalBookings == 25 && dashboard.RecentBookings.Count == 8 && dashboard.RecentStudios.All(s => s.CreatedAt is null), "authoritative dashboard and honest studio summaries");
var payload = await client.GetStringAsync("/api/admin/customers/1");
Check(!payload.Contains("password", StringComparison.OrdinalIgnoreCase) && !payload.Contains("token", StringComparison.OrdinalIgnoreCase), "no auth fields");
await app.StopAsync();

// Verify the production provider translates filters, projection, ordering and bounds without connecting.
using var pg = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql("Host=localhost;Database=not_used;Username=not_used").Options);
var sql = AdminController.BookingSummaries(AdminController.FilterBookings(pg.Bookings, new AdminBookingQuery {
    Search = "wedding", Status = BookingStatus.Pending, StudioId = studio.Id, CustomerId = 1,
    FromDate = new(2026, 10, 1), ToDate = new(2026, 10, 31)
}).OrderByDescending(b => b.BookingDate).ThenByDescending(b => b.Id)).Skip(10).Take(10).ToQueryString();
Check(sql.Contains("LIMIT") && sql.Contains("OFFSET") && sql.Contains("ORDER BY") && sql.Contains("BookingDate"), "PostgreSQL bounded booking query translation");
Check(AiWorkflowService.ReadProjection(pg.AiWorkflows).Take(20).ToQueryString().Contains("SELECT"), "PostgreSQL workflow monitoring projection translation");
Check(!AiWorkflowApprovalRules.CanReview("Admin", 5, 2) && !AiWorkflowApprovalRules.CanReview("Customer", 1, 2)
    && !AiWorkflowApprovalRules.CanReview("Studio", 4, 2) && AiWorkflowApprovalRules.CanReview("Studio", 2, 2), "selected owner review boundary");
var safeEvent = AiWorkflowService.SafeMonitoringEvent(new(Guid.NewGuid(), "PRIVATE TOKEN", "PRIVATE PROMPT", false, DateTime.UtcNow));
Check(safeEvent.EventType == "WorkflowEvent" && safeEvent.Stage == "Execution", "monitoring event metadata allowlist");
Console.WriteLine($"Passed {checks} Admin checks (HTTP/JWT, ephemeral SQLite, PostgreSQL SQL translation). No application database accessed.");

sealed class AdminTestDb(DbContextOptions<ApplicationDbContext> options) : ApplicationDbContext(options) {
    protected override void OnModelCreating(ModelBuilder builder) {
        base.OnModelCreating(builder);
        builder.Ignore<AiWorkflow>(); builder.Ignore<AiWorkflowEvent>(); builder.Ignore<AiWorkflowApproval>();
    }
}

sealed class AdminXmlRepository : Microsoft.AspNetCore.DataProtection.Repositories.IXmlRepository {
    private readonly List<System.Xml.Linq.XElement> elements = [];
    public IReadOnlyCollection<System.Xml.Linq.XElement> GetAllElements() { lock (elements) return elements.Select(e => new System.Xml.Linq.XElement(e)).ToArray(); }
    public void StoreElement(System.Xml.Linq.XElement element, string friendlyName) { lock (elements) elements.Add(new(element)); }
}
