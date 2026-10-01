using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using System.Data.Common;
using System.Net;
using System.Reflection;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

/// <summary>Real HTTP parser + orchestration + EF tracking/guard. Only external IO is replaced.</summary>
internal static class JourneyStudioBoundaryChecks
{
    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool value, string name) { if (!value) throw new Exception("Studio boundary: " + name); count++; }
        using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Phase1Checks.Fixtures.python-studio-stage.json")!;
        using var reader = new StreamReader(resource);
        var wire = await reader.ReadToEndAsync();
        using var response = JsonDocument.Parse(wire);
        var id = response.RootElement.GetProperty("workflowId").GetGuid();
        var studios = response.RootElement.GetProperty("output").GetProperty("rankedStudios").EnumerateArray()
            .Select(s => s.GetProperty("studioId").GetGuid()).ToArray();
        var packageId = Guid.NewGuid();
        var user = new ClaimsPrincipal(new ClaimsIdentity([new(ClaimTypes.NameIdentifier, "1"), new(ClaimTypes.Role, "Customer")], "test"));

        foreach (var missingStudio in new[] { false, true })
        {
            using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql()
                .AddInterceptors(new OfflineCommit(), new NoConnections()).Options);
            var commits = new List<AiWorkflow>();
            AiWorkflow? stored = null, tracked = null;
            var studioAvailable = true;
            using var handler = new StageResponse(wire, studios[0], packageId);
            using var http = new HttpClient(handler);
            var python = new InternalPythonWorkflowClient(http, new("http://offline.invalid", "offline-studio-boundary-test-token-32-characters"));
            var service = new AiJourneyService(TimeProvider.System,
                (customer, ct) => Task.FromResult(customer is 1 or 2),
                (workflowId, ct) => {
                    if (stored?.Id != workflowId) return Task.FromResult<AiWorkflow?>(null);
                    if (tracked is null) { tracked = Snapshot(stored); db.Attach(tracked); }
                    return Task.FromResult<AiWorkflow?>(tracked);
                },
                (studioId, ct) => Task.FromResult(studioAvailable && studios.Contains(studioId) && (!missingStudio || studioId != studios[1])
                    ? new Studio { Id = studioId, StudioName = "Authoritative studio " + Array.IndexOf(studios, studioId), Location = "Colombo" }
                    : null),
                async (workflow, create, ct) => {
                    if (create) db.AiWorkflows.Add(workflow);
                    else {
                        AiJourneyService.TrackNewEvents(db, workflow);
                        db.Entry(workflow).Property(w => w.UpdatedAt).IsModified = true;
                        Check(db.Entry(workflow).State == EntityState.Modified, "workflow update retains xmin fencing");
                        Check(db.Entry(workflow.Events[0]).State == EntityState.Unchanged, "persisted started event stays unchanged");
                        Check(db.ChangeTracker.Entries<AiWorkflowEvent>().Where(e => stored!.Events.All(old => old.Id != e.Entity.Id))
                            .All(e => e.State == EntityState.Added), "new events are inserts before the real guard runs");
                    }
                    // Runs the real ApplicationDbContext override and append-only guard.
                    // The interceptor suppresses database IO; connections are separately prohibited.
                    await db.SaveChangesAsync(ct);
                    db.ChangeTracker.AcceptAllChanges();
                    stored = Snapshot(workflow);
                    commits.Add(Snapshot(workflow));
                    tracked = workflow;
                },
                () => { db.ChangeTracker.Clear(); tracked = null; },
                (sid, pid) => Task.FromResult<PhotographyPackageResponseDto?>(sid == studios[0] && pid == packageId
                    ? new() { Id = pid, StudioId = sid, Name = "Authoritative package", DurationHours = 2 } : null),
                (sid, pid, customization) => Task.FromResult<PackagePriceCalculationResponseDto?>(sid == studios[0] && pid == packageId
                    ? new() { PackageId = pid, FinalPrice = 5000 } : null),
                (sid, pid, request, ct) => throw new Exception("Scheduling must remain blocked"),
                (workflow, request, ct) => throw new Exception("Validation must remain blocked"),
                (workflow, ct) => throw new Exception("Approval must remain blocked"), python.StageAsync);
            var request = new CreateAiWorkflowRequest { OperationId = id, Requirements = new() { PhotographyType = "Portrait", Location = "Colombo",
                MaximumBudget = 100000, CoverageHours = 2, EarliestDate = new(2030, 1, 1), LatestDate = new(2030, 1, 2) } };
            await using var app = BuildHost(service);
            await app.StartAsync();
            using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
            client.DefaultRequestHeaders.Authorization = new("Bearer", Token(1));
            using var created = await client.PostAsJsonAsync("/api/ai-workflows", request);
            Check(created.StatusCode == HttpStatusCode.Created, "authenticated fresh journey HTTP creation");
            var result = (await created.Content.ReadFromJsonAsync<AiWorkflowResponse>())!;
            Check(commits.Count == 2, "one initial claim and one terminal commit");
            Check(JourneyState.Read(commits[0]).Running is not null && commits[0].Status == AiWorkflowStatus.StudioMatching,
                "initial persisted state is Studio processing");
            Check(handler.Calls == 1 && result.Proposal is null && result.Journey!.Stage == "StudioMatching",
                "only the real Studio stage response is consumed");
            var persisted = JourneyState.Read(stored!);
            Check(persisted.Running is null && result.Journey!.Busy == false, "terminal state is resumable and no longer processing");
            Check(stored!.Events.All(e => e.StepName == "StudioMatching") && stored.Approvals.Count == 0,
                "no downstream completion, approval, or booking");
            if (!missingStudio)
            {
                Check(persisted.Entries.Select(e => e.Data.Kind).SequenceEqual(["started", "studio-option", "studio-option", "completed"]),
                    "valid FastAPI 200 commits the exact JourneyV1 completion chain");
                Check(result.Status == "StudioMatching" && result.Journey!.ErrorCode is null && result.Journey.StudioOptionId is null,
                    "Studio completed and waiting for customer selection");
                Check(result.Journey!.Options.Select(o => o.StudioId!.Value).SequenceEqual(studios) &&
                    result.Journey.Options.All(o => o.Name.StartsWith("Authoritative studio ")), "real reconciled studio options returned to Flutter");
                Check(stored.Events.All(e => Encoding.UTF8.GetByteCount(e.DetailsJson!) < 3500), "event payloads retain JourneyV1 bounds");
            }
            else
            {
                Check(result.Status == "Failed" && result.Journey!.ErrorCode == "unknown_studio_id" && result.Journey.Options.Count == 0,
                    "unreconciled studio fails closed without invented or partial choices");
                Check(persisted.Entries.Select(e => e.Data.Kind).SequenceEqual(["started", "failed"]),
                    "partially assembled options are discarded and safe failure is persisted");
            }
            var resumed = await service.GetAsync(id, user, default);
            Check(resumed.Journey!.Options.Count == result.Journey!.Options.Count && handler.Calls == 1, "resume never reruns matching");
            await service.CreateAsync(request, user, default);
            Check(handler.Calls == 1 && commits.Count == 2, "replay never creates another completion");

            if (!missingStudio)
            {
                var displayed = result.Journey!.Options[0];
                var command = new JourneyAction { OperationId = Guid.NewGuid(), Revision = result.Journey.Revision, OptionEventId = displayed.EventId };
                var path = $"/api/ai-workflows/{result.Id}/journey/studio";
                async Task ExpectRejected(JourneyAction body, HttpStatusCode status, string code, string name)
                {
                    using var rejectedResponse = await client.PostAsJsonAsync(path, body);
                    var payload = await rejectedResponse.Content.ReadFromJsonAsync<JsonElement>();
                    Check(rejectedResponse.StatusCode == status && payload.GetProperty("errorCode").GetString() == code, name);
                    Check(handler.Calls == 1 && commits.Count == 2, "rejected selection cannot claim or invoke Package");
                }
                client.DefaultRequestHeaders.Authorization = new("Bearer", Token(2));
                await ExpectRejected(command, HttpStatusCode.NotFound, "not_found", "another authenticated customer cannot select displayed option");
                client.DefaultRequestHeaders.Authorization = new("Bearer", Token(1));
                await ExpectRejected(new() { OperationId = Guid.NewGuid(), Revision = command.Revision, OptionEventId = Guid.NewGuid() },
                    HttpStatusCode.Conflict, "stale_option", "unknown option rejected");
                await ExpectRejected(new() { OperationId = Guid.NewGuid(), Revision = command.Revision, OptionEventId = displayed.StudioId },
                    HttpStatusCode.Conflict, "stale_option", "studio entity ID cannot substitute for displayed option event ID");
                await ExpectRejected(new() { OperationId = Guid.NewGuid(), Revision = command.Revision + 1, OptionEventId = displayed.EventId },
                    HttpStatusCode.Conflict, "concurrency_conflict", "wrong revision rejected");
                studioAvailable = false;
                await ExpectRejected(command, HttpStatusCode.Conflict, "stale_option", "removed authoritative studio remains rejected");
                studioAvailable = true;
                using (var premature = await client.PostAsJsonAsync($"/api/ai-workflows/{result.Id}/journey/package", command))
                    Check(premature.StatusCode == HttpStatusCode.Conflict && handler.PackageCalls == 0 && commits.Count == 2,
                        "Package selection cannot bypass Studio selection");
                // Exercise the same literal URL used by Flutter before any direct service selection.
                using var selected = await client.PostAsJsonAsync(path, command);
                Check(selected.StatusCode == HttpStatusCode.OK,
                    $"displayed studio selection HTTP status: expected 200, got {(int)selected.StatusCode}");
                var next = (await selected.Content.ReadFromJsonAsync<AiWorkflowResponse>())!;
                Check(handler.Calls == 2 && handler.PackageCalls == 1, "Package invoked exactly once after valid Studio selection");
                Check(next.Journey!.StudioOptionId == displayed.EventId && next.Journey.Stage == "PackageRecommendation" &&
                    !next.Journey.Busy && next.Journey.ErrorCode is null && next.Journey.PackageOptionId is null,
                    "selected studio persisted and Package completed waiting for selection");
                Check(next.Journey.Options.Single(o => o.Stage == "PackageRecommendation").StudioId == displayed.StudioId &&
                    next.Journey.ScheduleOptionId is null && next.Proposal is null, "authoritative package and downstream still blocked");
                Check(JourneyState.Read(commits[2]).Running?.Event.StepName == "PackageRecommendation" &&
                    JourneyState.Read(commits[2]).Selections["StudioMatching"].Data.StudioId == displayed.StudioId,
                    "selection and Package claim persisted together before invocation");
                using var replayed = await client.PostAsJsonAsync(path, command);
                Check(replayed.StatusCode == HttpStatusCode.OK && handler.PackageCalls == 1 && commits.Count == 4,
                    "HTTP replay never invokes Package twice");
                using var stale = await client.PostAsJsonAsync(path, new JourneyAction { OperationId = Guid.NewGuid(), Revision = command.Revision, OptionEventId = displayed.EventId });
                Check(stale.StatusCode == HttpStatusCode.Conflict && handler.PackageCalls == 1 && commits.Count == 4,
                    "old selection revision cannot dispatch again");
                Check(stored!.Events.All(e => Encoding.UTF8.GetByteCount(e.DetailsJson!) < 3500), "selected and Package events retain bounds");
                using var resumedHttp = await client.GetAsync($"/api/ai-workflows/{result.Id}");
                var saved = (await resumedHttp.Content.ReadFromJsonAsync<AiWorkflowResponse>())!;
                Check(saved.Journey!.StudioOptionId == displayed.EventId, "GET resumes persisted Studio selection");
            }
            await app.StopAsync();

            // An existing audit mutation must still fail; the tracking fix is not an upsert or guard bypass.
            tracked!.Events[0].Summary = "attempted audit rewrite";
            AiJourneyService.TrackNewEvents(db, tracked);
            var rejected = false;
            try { AiWorkflowPersistenceGuard.Validate(db.ChangeTracker); } catch (InvalidOperationException) { rejected = true; }
            Check(rejected, "existing event modification remains prohibited");
            Check(db.ChangeTracker.AutoDetectChangesEnabled, "normal change detection restored");
        }
        return count;
    }

    private static readonly SymmetricSecurityKey Key = new(Encoding.UTF8.GetBytes("offline-journey-selection-regression-key-32-bytes"));
    private static string Token(int customer) => new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
        issuer: "offline", audience: "journey", claims: [new(ClaimTypes.NameIdentifier, customer.ToString()), new(ClaimTypes.Role, "Customer")],
        expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new(Key, SecurityAlgorithms.HmacSha256)));

    private static WebApplication BuildHost(AiJourneyService service)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddControllers().AddApplicationPart(typeof(AiWorkflowsController).Assembly).AddControllersAsServices();
        // These customer endpoints exclusively use IAiJourneyService; legacy service must never be accessed.
        builder.Services.AddSingleton(new AiWorkflowsController(null!, service));
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
            options.TokenValidationParameters = new() { ValidateIssuer = true, ValidIssuer = "offline", ValidateAudience = true,
                ValidAudience = "journey", ValidateLifetime = true, ValidateIssuerSigningKey = true, IssuerSigningKey = Key, ClockSkew = TimeSpan.Zero });
        builder.Services.AddAuthorization();
        var app = builder.Build();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers();
        return app;
    }

    private static AiWorkflow Snapshot(AiWorkflow w) => new() { Id = w.Id, CustomerId = w.CustomerId, Status = w.Status,
        CurrentStep = w.CurrentStep, NormalizedRequirementsJson = w.NormalizedRequirementsJson, CreatedAt = w.CreatedAt,
        UpdatedAt = w.UpdatedAt, ExpiresAt = w.ExpiresAt, RowVersion = w.RowVersion,
        Events = w.Events.Select(e => new AiWorkflowEvent { Id = e.Id, WorkflowId = e.WorkflowId, EventType = e.EventType,
            StepName = e.StepName, DetailsJson = e.DetailsJson, Summary = e.Summary, Success = e.Success, CreatedAt = e.CreatedAt }).ToList() };

    private sealed class StageResponse(string json, Guid studioId, Guid packageId) : HttpMessageHandler
    {
        public int Calls, PackageCalls;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Calls++;
            if (request.Method != HttpMethod.Post || !request.RequestUri!.AbsolutePath.EndsWith("/stage"))
                throw new Exception("Unexpected agent dispatch");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
            var input = body.RootElement;
            var stage = input.GetProperty("stage").GetString();
            var payload = json;
            if (stage == "PackageRecommendation")
            {
                PackageCalls++;
                if (input.GetProperty("studios").GetProperty("rankedStudios")[0].GetProperty("studioId").GetGuid() != studioId)
                    throw new Exception("Package input did not use selected authoritative studio");
                payload = JsonSerializer.Serialize(new { workflowId = request.RequestUri!.Segments[^2].Trim('/'),
                    operationId = input.GetProperty("operationId").GetGuid(), stage,
                    output = new { rankedPackages = new[] { new { studioId, packageId, explanationSummary = "Matches coverage.",
                        customization = new { extraHours = 0 }, pricing = new { finalPrice = 5000 } } }, unmetPreferences = Array.Empty<string>() },
                    errorCode = (string?)null });
            }
            else if (stage != "StudioMatching") throw new Exception("Downstream agent must remain blocked");
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(payload, Encoding.UTF8, "application/json") };
        }
    }
    private sealed class OfflineCommit : SaveChangesInterceptor
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData data, InterceptionResult<int> result, CancellationToken ct = default)
            => ValueTask.FromResult(InterceptionResult<int>.SuppressWithResult(1));
    }
    private sealed class NoConnections : DbConnectionInterceptor
    {
        public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData data, InterceptionResult result)
            => throw new Exception("Database connections are forbidden in this regression");
        public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection, ConnectionEventData data, InterceptionResult result, CancellationToken ct = default)
            => throw new Exception("Database connections are forbidden in this regression");
    }
}
