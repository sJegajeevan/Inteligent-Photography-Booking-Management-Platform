using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;
using PackageService = PhotographyBooking.Api.Services.PhotographyPackageService;

// Explicit opt-in. Fixed isolated loopback cluster, generated database name, no production config.
internal static class AiWorkflowLiveChecks
{
    public static async Task RunAsync()
    {
        var database = "ai_checks_" + Guid.NewGuid().ToString("N");
        const string adminConnection = "Host=127.0.0.1;Port=55439;Username=ai_test;Database=postgres;Pooling=false";
        await using var admin = new NpgsqlConnection(adminConnection);
        await admin.OpenAsync();
        await using (var command = new NpgsqlCommand($"CREATE DATABASE {database}", admin)) await command.ExecuteNonQueryAsync();
        try { await CheckAsync(adminConnection.Replace("Database=postgres", "Database=" + database)); }
        finally {
            NpgsqlConnection.ClearAllPools();
            await using var command = new NpgsqlCommand($"DROP DATABASE {database} WITH (FORCE)", admin);
            await command.ExecuteNonQueryAsync();
        }
    }

    private static async Task CheckAsync(string connection)
    {
        var count = 0;
        void Check(bool value, string name) { if (!value) throw new Exception("FAILED live integration: " + name); count++; }
        var options = new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql(connection).Options;
        await using (var db = new ApplicationDbContext(options)) {
            await db.Database.EnsureCreatedAsync(); // New disposable database ONLY. Never migrations/application DB.
            db.Users.AddRange(new User { Id = 1, Role = "Customer", Email = "customer@test", FullName = "Test Customer" },
                new User { Id = 2, Role = "Studio", Email = "studio@test" }, new User { Id = 3, Role = "Studio", Email = "other@test" });
            var studio = new Studio { UserId = 2, StudioName = "Integration Studio", Location = "Jaffna", PhotographyTypes = "Wedding", StartingPrice = 40000 };
            db.Studios.Add(studio);
            db.PhotographyPackages.Add(new PhotographyPackage { Studio = studio, Name = "Integration Wedding", BasePrice = 50000,
                DurationHours = 4, NumberOfPhotographers = 1, ExtraHourRate = 1000, Status = PhotographyPackageStatus.Active });
            for (var day = 1; day <= 12; day++) db.StudioAvailabilities.Add(new StudioAvailability {
                Studio = studio, Date = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(day + 30), IsAvailable = true,
                StartTime = new(9, 0), EndTime = new(18, 0) });
            await db.SaveChangesAsync();
        }
        var token = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("isolated-ai-integration-jwt-signing-key-32-bytes"));
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddControllers().AddApplicationPart(typeof(AiWorkflowsController).Assembly);
        builder.Services.AddDbContext<ApplicationDbContext>(o => o.UseNpgsql(connection));
        builder.Services.AddSingleton<TimeProvider>(TimeProvider.System);
        builder.Services.AddSingleton<DistanceService>();
        builder.Services.AddScoped<StudioDiscoveryService>();
        builder.Services.AddScoped<PackageService>();
        builder.Services.AddScoped<PackagePriceCalculationService>();
        builder.Services.AddScoped<BookingSlotValidationService>();
        builder.Services.AddScoped<SchedulingCandidateService>();
        builder.Services.AddScoped<RecommendationValidationService>();
        builder.Services.AddScoped<FinalRecommendationValidationService>();
        builder.Services.AddScoped<CanonicalProposalService>();
        builder.Services.AddScoped<AiWorkflowPublicationService>();
        builder.Services.AddScoped<AiWorkflowApprovalService>();
        builder.Services.AddScoped<AiWorkflowExecutionService>();
        builder.Services.AddScoped<AiWorkflowService>();
        builder.Services.AddSingleton(new PythonWorkflowOptions("http://127.0.0.1:55441", token, 90));
        builder.Services.AddHttpClient<InternalPythonWorkflowClient>().RemoveAllLoggers();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o => o.TokenValidationParameters = new() {
            ValidateIssuer = false, ValidateAudience = false, ValidateLifetime = true, ValidateIssuerSigningKey = true, IssuerSigningKey = key });
        builder.Services.AddAuthorization();
        await using var app = builder.Build();
        app.UseAuthentication(); app.UseAuthorization(); app.MapControllers();
        await app.StartAsync();
        var python = Path.GetFullPath("agentic-ai/.venv/Scripts/python.exe");
        var start = new ProcessStartInfo(python) { WorkingDirectory = Path.GetFullPath("agentic-ai"),
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var arg in new[] { "-m", "uvicorn", "tests.integration_app:create_integration_app", "--factory", "--host", "127.0.0.1", "--port", "55441", "--log-level", "warning" }) start.ArgumentList.Add(arg);
        start.Environment["ASPNET_API_BASE_URL"] = app.Urls.Single();
        start.Environment["INTERNAL_WORKFLOW_TOKEN"] = token;
        using var process = Process.Start(start)!;
        var stderr = process.StandardError.ReadToEndAsync();
        var stdout = process.StandardOutput.ReadToEndAsync();
        try {
            using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()), Timeout = TimeSpan.FromSeconds(100) };
            using var health = new HttpClient();
            var ready = false;
            for (var i = 0; i < 50; i++) {
                if (process.HasExited) throw new Exception("FastAPI startup failed: " + await stderr);
                try { ready = (await health.GetAsync("http://127.0.0.1:55441/health")).IsSuccessStatusCode; } catch (HttpRequestException) { }
                if (ready) break;
                await Task.Delay(200);
            }
            Check(ready, "FastAPI starts and health responds");
            using (var unauthorized = await health.PostAsJsonAsync("http://127.0.0.1:55441/internal/ai-workflows/" + Guid.NewGuid() + "/run", new { }))
                Check(unauthorized.StatusCode == HttpStatusCode.Unauthorized, "internal endpoint rejects missing token");
            string Jwt(int id, string role) => new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
                claims: [new(ClaimTypes.NameIdentifier, id.ToString()), new(ClaimTypes.Role, role)],
                expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new(key, SecurityAlgorithms.HmacSha256)));
            async Task<(HttpStatusCode Status, JsonElement Body)> Post(string path, object body, int id, string role) {
                using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(body) };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Jwt(id, role));
                using var response = await client.SendAsync(request);
                var text = await response.Content.ReadAsStringAsync();
                return (response.StatusCode, string.IsNullOrEmpty(text) ? default : JsonDocument.Parse(text).RootElement.Clone());
            }
            async Task<JsonElement> Create(int day, decimal budget = 100000, string type = "Wedding") {
                var date = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(day + 30);
                var response = await Post("/api/ai-workflows", new { requirements = new {
                    photographyType = type, location = "Jaffna", maximumBudget = budget, coverageHours = 4,
                    earliestDate = date, latestDate = date, requestedServices = Array.Empty<string>() } }, 1, "Customer");
                Check(response.Status == HttpStatusCode.Created, "workflow creation HTTP 201: " + response.Body);
                return response.Body;
            }
            async Task<int> Bookings() { await using var db = new ApplicationDbContext(options); return await db.Bookings.CountAsync(); }
            var fresh = await Create(1);
            Check(fresh.GetProperty("status").GetString() == "AwaitingApproval", "real four-agent HTTP workflow: " + fresh);
            Check(fresh.GetProperty("proposalVersion").GetInt32() == 1 && fresh.GetProperty("proposal").GetProperty("version").GetInt32() == 1, "persisted initial version 1");
            Check(await Bookings() == 0, "no booking before approval");
            var id = fresh.GetProperty("id").GetGuid();
            Check((await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 3, "Studio")).Status == HttpStatusCode.NotFound, "non-owner approval denied");
            Check((await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 2 }, 2, "Studio")).Status == HttpStatusCode.Conflict, "stale version rejected");
            var approved = await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 2, "Studio");
            Check(approved.Status == HttpStatusCode.OK && approved.Body.GetProperty("status").GetString() == "Approved", "fresh approval: " + approved.Body);
            Check(await Bookings() == 1, "real booking created after approval");
            Check((await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 2, "Studio")).Status == HttpStatusCode.Conflict && await Bookings() == 1, "duplicate approval does not create booking");
            await using (var db = new ApplicationDbContext(options)) {
                var booking = await db.Bookings.SingleAsync();
                Check(booking.CustomerId == 1 && booking.Status == BookingStatus.Pending && booking.TotalPrice == 50000 &&
                    booking.StartTime == new TimeOnly(9, 0) && booking.EndTime == new TimeOnly(13, 0), "booking ownership, status, authoritative price and duration");
                Check(await db.BookingStatusHistories.CountAsync() == 1 && await db.Notifications.CountAsync() == 1, "history and notification committed");
                Check(await db.AiWorkflowApprovals.CountAsync() == 1, "approval persisted once");
            }
            var rejected = await Create(2); id = rejected.GetProperty("id").GetGuid();
            Check((await Post($"/api/ai-workflows/{id}/reject", new { proposalVersion = 1, reason = "Unavailable" }, 2, "Studio")).Body.GetProperty("status").GetString() == "Rejected", "rejection works");
            Check(await Bookings() == 1, "no booking after rejection");
            var stale = await Create(3); id = stale.GetProperty("id").GetGuid();
            await using (var db = new ApplicationDbContext(options)) {
                var slot = await db.StudioAvailabilities.SingleAsync(a => a.Date == DateOnly.FromDateTime(DateTime.UtcNow).AddDays(33));
                slot.IsAvailable = false; await db.SaveChangesAsync(); // isolated fixture change
            }
            var invalid = await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 2, "Studio");
            Check(invalid.Status == HttpStatusCode.OK && invalid.Body.GetProperty("status").GetString() == "RevalidationRequired", "changed availability revalidated");
            Check(await Bookings() == 1, "no booking when validation fails");
            var none = await Create(4, type: "Underwater");
            Check(none.GetProperty("status").GetString() == "Failed" && none.GetProperty("failure").GetProperty("stage").GetString() == "StudioMatching" &&
                none.GetProperty("failure").GetProperty("code").GetString() == "no_matching_studios", "safe node failure persisted and returned");
            var budget = await Create(4, budget: 49999);
            Check(budget.GetProperty("status").GetString() == "Failed" &&
                budget.GetProperty("failure").GetProperty("stage").GetString() == "PackageRecommendation" &&
                budget.GetProperty("failure").GetProperty("code").GetString() == "no_matching_packages", "package budget mismatch identifies node");
            using (var request = new HttpRequestMessage(HttpMethod.Get, "/api/ai-workflows/" + budget.GetProperty("id").GetGuid())) {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Jwt(1, "Customer"));
                using var response = await client.SendAsync(request);
                var reread = await response.Content.ReadFromJsonAsync<JsonElement>();
                Check(response.IsSuccessStatusCode && reread.GetProperty("failure").GetProperty("code").GetString() == "no_matching_packages",
                    "failure diagnostic survives database reload");
            }
            // Two independent valid proposals race for the same studio/time: only one may book.
            var a = await Create(5); var b = await Create(5);
            var concurrent = await Task.WhenAll(new[] { a, b }.Select(w => Post($"/api/ai-workflows/{w.GetProperty("id").GetGuid()}/approve", new { proposalVersion = 1 }, 2, "Studio")));
            Check(concurrent.Count(r => r.Status == HttpStatusCode.OK && r.Body.GetProperty("status").GetString() == "Approved") == 1 && await Bookings() == 2,
                "concurrent overlapping approvals create exactly one booking");
            Check(concurrent.Count(r => r.Status == HttpStatusCode.OK && r.Body.GetProperty("status").GetString() == "RevalidationRequired") == 1,
                "competing proposal safely requires revalidation");
            var rollback = await Create(6); id = rollback.GetProperty("id").GetGuid();
            await using (var db = new ApplicationDbContext(options)) {
                // Inject a failure at the final approval save AFTER the booking insert.
                // This constraint exists only in this generated disposable database.
                await db.Database.ExecuteSqlRawAsync("ALTER TABLE public.\"AiWorkflowApprovals\" ADD CONSTRAINT test_approval_failure CHECK (\"Decision\" <> 'Approved') NOT VALID");
            }
            var failed = await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 2, "Studio");
            Check((int)failed.Status >= 400, "injected approval persistence failure rejected");
            await using (var db = new ApplicationDbContext(options)) {
                Check(await db.Bookings.CountAsync() == 2, "failed transaction rolls back booking insert");
                Check(await db.BookingStatusHistories.CountAsync() == 2 && await db.Notifications.CountAsync() == 2,
                    "failed transaction rolls back history and notification");
                Check(!await db.AiWorkflowApprovals.AnyAsync(a => a.WorkflowId == id) &&
                    !await db.AiWorkflowEvents.AnyAsync(e => e.WorkflowId == id && e.EventType == "WorkflowBookingCreated") &&
                    (await db.AiWorkflows.SingleAsync(w => w.Id == id)).Status == AiWorkflowStatus.AwaitingApproval,
                    "failed transaction rolls back approval, booking event and workflow state");
                await db.Database.ExecuteSqlRawAsync("ALTER TABLE public.\"AiWorkflowApprovals\" DROP CONSTRAINT test_approval_failure");
            }
            Check((await Post($"/api/ai-workflows/{id}/approve", new { proposalVersion = 1 }, 2, "Studio")).Status == HttpStatusCode.OK && await Bookings() == 3,
                "retry after rollback creates exactly one booking");
            Console.WriteLine($"Passed {count} live PostgreSQL/.NET/FastAPI/four-agent checks. Only Gemini ranking is mocked; disposable database removed.");
        }
        finally {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync();
            await stderr; await stdout;
            await app.StopAsync();
        }
    }
}
