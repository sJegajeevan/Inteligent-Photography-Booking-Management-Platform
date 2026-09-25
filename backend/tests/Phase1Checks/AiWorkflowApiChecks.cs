using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class AiWorkflowApiChecks
{
    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool ok, string name) { if (!ok) throw new Exception("FAILED workflow API: " + name); count++; }
        var users = new[] { new User { Id = 1, Role = "Customer" }, new User { Id = 2, Role = "Customer" },
            new User { Id = 3, Role = "Studio" }, new User { Id = 4, Role = "Studio" }, new User { Id = 5, Role = "Admin" } };
        var studio = new Studio { UserId = 3 };
        var own = new AiWorkflow { CustomerId = 1, Status = AiWorkflowStatus.Validation, CurrentStep = "Validation",
            CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow, ExpiresAt = DateTime.UtcNow.AddHours(1),
            SelectedStudioId = studio.Id, SelectedStudio = studio, NormalizedRequirementsJson = "PRIVATE internal requirements" };
        var other = new AiWorkflow { CustomerId = 2, CreatedAt = DateTime.UtcNow.AddMinutes(-1), ExpiresAt = DateTime.UtcNow.AddHours(1) };
        var rows = new List<AiWorkflow> { own, other };
        var saves = 0; var decisions = 0;
        Exception? failure = null;
        AiWorkflowDecisionResult decisionResult = new(null, AiWorkflowStatus.Approved);
        (Guid Id, int Version, AiApprovalDecision Decision, string? Reason, int Actor)? lastDecision = null;
        var service = new AiWorkflowService(TimeProvider.System,
            (id, ct) => { ct.ThrowIfCancellationRequested(); if (failure is not null) throw failure;
                return Task.FromResult(users.SingleOrDefault(u => u.Id == id)); },
            (actor, id, ct) => Task.FromResult(AiWorkflowService.Scope(rows.AsQueryable(), actor).SingleOrDefault(w => w.Id == id)),
            (actor, query, ct) => Task.FromResult(AiWorkflowService.PageQuery(AiWorkflowService.Scope(rows.AsQueryable(), actor), query).ToList()),
            (workflow, ct) => { saves++; rows.Add(workflow); return Task.CompletedTask; },
            (id, version, decision, reason, principal, ct) =>
            {
                decisions++;
                lastDecision = (id, version, decision, reason, int.Parse(principal.FindFirstValue(ClaimTypes.NameIdentifier)!));
                return Task.FromResult(decisionResult);
            });

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("offline-workflow-api-check-key-at-least-32-bytes"));
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
        builder.Logging.ClearProviders(); builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddControllers().AddApplicationPart(typeof(AiWorkflowsController).Assembly);
        builder.Services.AddSingleton(service);
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
            options.TokenValidationParameters = new TokenValidationParameters { ValidateIssuer = true, ValidIssuer = "offline",
                ValidateAudience = true, ValidAudience = "workflow-checks", ValidateLifetime = true,
                ValidateIssuerSigningKey = true, IssuerSigningKey = key, ClockSkew = TimeSpan.Zero });
        builder.Services.AddAuthorization();
        await using var app = builder.Build();
        app.UseAuthentication(); app.UseAuthorization(); app.MapControllers(); await app.StartAsync();
        try
        {
            using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
            string Token(int id, string? role = null) => new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
                issuer: "offline", audience: "workflow-checks", claims: [new(ClaimTypes.NameIdentifier, id.ToString()),
                    new(ClaimTypes.Role, role ?? users.Single(u => u.Id == id).Role)], expires: DateTime.UtcNow.AddMinutes(5),
                signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)));
            async Task<string> Send(string method, string path, int status, int? actor = 1, string? body = null, string? role = null)
            {
                using var request = new HttpRequestMessage(new HttpMethod(method), path);
                if (actor is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Token(actor.Value, role));
                if (body is not null) request.Content = new StringContent(body, Encoding.UTF8, "application/json");
                using var response = await client.SendAsync(request);
                var text = await response.Content.ReadAsStringAsync();
                Check((int)response.StatusCode == status, method + " " + path + " expected " + status + " actual " + (int)response.StatusCode);
                Check(!text.Contains("PRIVATE") && !text.Contains("stackTrace") && !text.Contains("RowVersion") &&
                    !text.Contains("xmin") && !text.Contains("PasswordHash"), "HTTP data sanitized");
                return text;
            }
            const string root = "/api/ai-workflows";
            var invalidTokens = new[]
            {
                "not-a-jwt",
                new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
                    issuer: "offline", audience: "workflow-checks",
                    claims: [new(ClaimTypes.NameIdentifier, "1"), new(ClaimTypes.Role, "Customer")],
                    expires: DateTime.UtcNow.AddMinutes(-5),
                    signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256))),
                new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
                    issuer: "offline", audience: "workflow-checks",
                    claims: [new(ClaimTypes.NameIdentifier, "1"), new(ClaimTypes.Role, "Customer")],
                    expires: DateTime.UtcNow.AddMinutes(5),
                    signingCredentials: new SigningCredentials(new SymmetricSecurityKey(
                        Encoding.UTF8.GetBytes("wrong-offline-signing-key-at-least-32-bytes")), SecurityAlgorithms.HmacSha256)))
            };
            foreach (var token in invalidTokens)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, root);
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                using var response = await client.SendAsync(request);
                Check(response.StatusCode == System.Net.HttpStatusCode.Unauthorized, "invalid JWT rejected by middleware");
                Check(string.IsNullOrEmpty(await response.Content.ReadAsStringAsync()), "JWT failure exposes no details");
            }
            var body = JsonSerializer.Serialize(new { requirements = new { photographyType = "  Wedding  ", location = " Jaffna ",
                maximumBudget = 100000, earliestDate = "2027-12-01", latestDate = "2027-12-02", coverageHours = 4,
                requestedServices = new[] { " Photography ", "Photography" }, notes = "PRIVATE prompt secret GPS" } });
            foreach (var (method, path, content) in new[] { ("POST", root, body), ("GET", root, (string?)null),
                ("GET", root + "/" + own.Id, (string?)null), ("POST", root + "/" + own.Id + "/approve", "{\"proposalVersion\":1}"),
                ("POST", root + "/" + own.Id + "/reject", "{\"proposalVersion\":1,\"reason\":\"No\"}") })
                await Send(method, path, 401, null, content);
            foreach (var actor in new[] { 3, 5 }) await Send("POST", root, 404, actor, body);
            Check(saves == 0, "unauthorized creation never writes");
            var created = JsonNode.Parse(await Send("POST", root, 201, body: body))!;
            var saved = rows.Last();
            Check(saves == 1 && saved.CustomerId == 1 && created["id"]!.GetValue<Guid>() == saved.Id, "identity owns created workflow");
            Check(saved.Status == AiWorkflowStatus.Submitted && saved.CurrentStep == "Submitted" && saved.ProposalVersion == 0 &&
                saved.FinalProposalJson is null && saved.SelectedStudioId is null && saved.Approvals.Count == 0, "submission only; no fake proposal or approval");
            var normalized = CanonicalProposalService.Read<CustomerPhotographyRequirements>(saved.NormalizedRequirementsJson);
            Check(normalized.PhotographyType == "Wedding" && normalized.Location == "Jaffna" && normalized.RequestedServices.Count == 1 &&
                normalized.Notes is null && !saved.NormalizedRequirementsJson.Contains("PRIVATE"), "bounded normalized requirements only");
            Check(saved.Events.Single().EventType == "WorkflowSubmitted" && saved.Events.Single().Summary == "Customer workflow submitted." &&
                saved.Events.Single().WorkflowId == saved.Id, "atomic aggregate creation event");
            Check(saved.ExpiresAt - saved.CreatedAt == TimeSpan.FromHours(24), "server submission expiry");
            foreach (var extra in new[] { "customerId", "proposalJson", "reviewerId", "nearby", "prompt" })
            {
                var json = JsonNode.Parse(body)!; json[extra] = "PRIVATE";
                await Send("POST", root, 400, body: json.ToJsonString());
            }
            var nested = JsonNode.Parse(body)!; nested["requirements"]!["customerId"] = 5;
            await Send("POST", root, 400, body: nested.ToJsonString());
            foreach (var invalid in new[] { "PRIVATE invalid JSON", "{}", "null", "{\"requirements\":null}" })
                await Send("POST", root, 400, body: invalid);
            var bad = JsonNode.Parse(body)!; bad["requirements"]!["coverageHours"] = -1;
            await Send("POST", root, 400, body: bad.ToJsonString());
            Check(saves == 1, "malformed/extra requests cannot persist");
            await Send("GET", root + "/" + own.Id, 200);
            var inaccessible = await Send("GET", root + "/" + own.Id, 404, 2);
            Check(inaccessible == await Send("GET", root + "/" + Guid.NewGuid(), 404, 2), "missing and foreign workflow opaque");
            await Send("GET", root + "/" + own.Id, 200, 3);
            await Send("GET", root + "/" + own.Id, 404, 4);
            await Send("GET", root + "/" + own.Id, 200, 5);
            await Send("GET", root + "/" + own.Id, 404, 1, role: "Admin");
            await Send("GET", root + "/" + own.Id, 404, 999, role: "Customer");
            await Send("GET", root + "/PRIVATE-invalid-uuid", 400);
            foreach (var (actor, expected) in new[] { (1, 2), (2, 1), (3, 1), (4, 0), (5, 3) })
            {
                var page = JsonNode.Parse(await Send("GET", root, 200, actor))!;
                Check(page["items"]!.AsArray().Count == expected, "role-scoped list " + actor);
            }
            var first = JsonNode.Parse(await Send("GET", root + "?pageSize=1", 200))!;
            Check(first["hasMore"]!.GetValue<bool>() && first["items"]!.AsArray().Count == 1, "bounded pagination");
            var second = JsonNode.Parse(await Send("GET", root + "?pageSize=1&page=2", 200))!;
            Check(first["items"]![0]!["id"]!.ToString() != second["items"]![0]!["id"]!.ToString(), "stable disjoint pages");
            var filtered = JsonNode.Parse(await Send("GET", root + "?status=Validation", 200))!;
            Check(filtered["items"]!.AsArray().Count == 1, "status filter");
            foreach (var query in new[] { "page=0", "page=10001", "pageSize=101", "pageSize=-1", "status=999", "status=PRIVATE", "page=PRIVATE" })
                await Send("GET", root + "?" + query, 400);

            var approve = root + "/" + own.Id + "/approve";
            var reject = root + "/" + own.Id + "/reject";
            await Send("POST", approve, 404, 1, "{\"proposalVersion\":1}");
            await Send("POST", reject, 404, 1, "{\"proposalVersion\":1,\"reason\":\"No\"}");
            Check(decisions == 0, "customer cannot reach decision service");
            foreach (var actor in new[] { 3, 5 })
            {
                decisionResult = new(null, AiWorkflowStatus.Approved);
                var approved = JsonNode.Parse(await Send("POST", approve, 200, actor, "{\"proposalVersion\":7}"))!;
                Check(approved["status"]!.ToString() == "Approved" && lastDecision is { Version: 7, Decision: AiApprovalDecision.Approved, Reason: null } &&
                    lastDecision.Value.Actor == actor, "approve delegates version/auth identity");
                decisionResult = new(null, AiWorkflowStatus.Rejected);
                var rejected = JsonNode.Parse(await Send("POST", reject, 200, actor, "{\"proposalVersion\":7,\"reason\":\"No thanks\"}"))!;
                Check(rejected["status"]!.ToString() == "Rejected" && lastDecision is { Decision: AiApprovalDecision.Rejected, Reason: "No thanks" }, "reject delegates exact reason/version");
            }
            var before = decisions;
            foreach (var invalid in new[] { "{}", "{\"proposalVersion\":0}", "{\"proposalVersion\":1,\"reviewerId\":5}",
                "{\"proposalVersion\":1,\"proposalJson\":\"PRIVATE\"}", "{\"proposalVersion\":1,\"reason\":\"PRIVATE\"}" })
                await Send("POST", approve, 400, 3, invalid);
            foreach (var reason in new[] { "", " ", new string('x', 1001) })
                await Send("POST", reject, 400, 3, JsonSerializer.Serialize(new { proposalVersion = 1, reason }));
            Check(decisions == before, "malformed decisions never reach writer");
            foreach (var (error, status) in new[] { ("Forbidden", 404), ("NotFound", 404), ("StaleProposal", 409),
                ("AlreadyDecided", 409), ("NotAwaitingApproval", 409), ("Expired", 409), ("invalid_workflow_state", 409),
                ("backend_unavailable", 500), ("PRIVATE SQL stack", 500) })
            {
                decisionResult = new(error, null);
                await Send("POST", approve, status, 3, "{\"proposalVersion\":1}");
            }
            decisionResult = new("NotFound", null);
            await Send("POST", approve, 404, 4, "{\"proposalVersion\":1}");
            await Send("POST", reject, 404, 4, "{\"proposalVersion\":1,\"reason\":\"No\"}");
            foreach (var code in new[] { "price_changed", "slot_unavailable", "booking_conflict", "stale_recommendation", "budget_failure" })
            {
                decisionResult = new(code, AiWorkflowStatus.RevalidationRequired);
                var response = JsonNode.Parse(await Send("POST", approve, 200, 3, "{\"proposalVersion\":1}"))!;
                Check(response["status"]!.ToString() == "RevalidationRequired" && response["errorCode"]!.ToString() == code, "explicit revalidation status " + code);
            }
            foreach (var exception in new Exception[] { new DbUpdateConcurrencyException("PRIVATE"),
                new PostgresException("PRIVATE", "ERROR", "ERROR", "40001"),
                new DbUpdateException("PRIVATE", new PostgresException("PRIVATE", "ERROR", "ERROR", "23505")) })
            {
                failure = exception;
                await Send("POST", approve, 409, 3, "{\"proposalVersion\":1}");
            }
            failure = new InvalidOperationException("PRIVATE SQL credentials");
            foreach (var (method, path, content) in new[] { ("GET", root, (string?)null), ("GET", root + "/" + own.Id, (string?)null),
                ("POST", root, body), ("POST", approve, "{\"proposalVersion\":1}"), ("POST", reject, "{\"proposalVersion\":1,\"reason\":\"No\"}") })
            {
                var response = JsonNode.Parse(await Send(method, path, 500, 3, content))!;
                Check(response["title"]!.ToString() == "Unable to process the workflow request.", "fixed 500 problem");
            }
            failure = null;
            own.FinalProposalJson = "PRIVATE corrupted storage";
            await Send("GET", root + "/" + own.Id, 500);
            own.FinalProposalJson = null;
            Check(saves == 1 && rows.All(w => w.Approvals.Count == 0), "only creation persistence invoked by HTTP mocks");
        }
        finally { await app.StopAsync(); }

        // Query translation is checked offline against the real Npgsql model, not an in-memory filter alone.
        using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql().Options);
        foreach (var actor in users.Where(u => u.Id is 1 or 3 or 5))
        {
            var sql = AiWorkflowService.PageQuery(AiWorkflowService.Scope(db.AiWorkflows.AsNoTracking(), actor),
                new() { Status = "AwaitingApproval", Page = 2, PageSize = 10 }).ToQueryString();
            Check(sql.Contains("WHERE") && sql.Contains("LIMIT") && sql.Contains("OFFSET") && sql.Contains("ORDER BY"), "DB-side filtering/pagination " + actor.Role);
            Check(actor.Role != "Studio" || sql.Contains("JOIN") && sql.Contains("UserId"), "DB-side selected studio ownership");
            Check(actor.Role != "Customer" || sql.Contains("CustomerId\" ="), "DB-side customer ownership");
        }
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await service.GetAsync(own.Id, new ClaimsPrincipal(), cancelled.Token); Check(false, "cancellation"); }
        catch (OperationCanceledException) { Check(true, "cancellation propagates"); }
        // Change tracking only: exercise append-only decisions without saving or opening a connection.
        var reviewed = new AiWorkflowApproval { WorkflowId = own.Id, ProposalVersion = 1,
            ReviewerUserId = 3, Decision = AiApprovalDecision.Rejected,
            ProposalSnapshotJson = "reviewed snapshot", Reason = "Original reason" };
        db.Attach(reviewed);
        reviewed.ProposalSnapshotJson = "replacement snapshot";
        var blocked = false;
        try { AiWorkflowPersistenceGuard.Validate(db.ChangeTracker); }
        catch (InvalidOperationException) { blocked = true; }
        Check(blocked, "reviewed snapshot modification blocked");
        db.Entry(reviewed).State = EntityState.Deleted;
        blocked = false;
        try { AiWorkflowPersistenceGuard.Validate(db.ChangeTracker); }
        catch (InvalidOperationException) { blocked = true; }
        Check(blocked, "reviewed decision deletion blocked");
        return count;
    }
}
