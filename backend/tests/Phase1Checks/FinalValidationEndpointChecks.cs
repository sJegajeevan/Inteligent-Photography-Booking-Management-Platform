using System.Reflection;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Services;

internal static class FinalValidationEndpointChecks
{
    private sealed class Clock : TimeProvider
    {
        public bool Throw { get; set; }
        public override DateTimeOffset GetUtcNow() => Throw
            ? throw new InvalidOperationException("PRIVATE exception stack connection details")
            : new(2026, 9, 21, 0, 0, 0, TimeSpan.Zero);
    }

    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool value, string name) { if (!value) throw new Exception("FAILED validation endpoint: " + name); count++; }
        var studioId = Guid.NewGuid(); var packageId = Guid.NewGuid(); var serviceId = Guid.NewGuid();
        var day = new DateOnly(2026, 9, 22);
        var clock = new Clock();
        var reads = 0; var failRead = false;
        CancellationTokenSource? cancelDuringRead = null;
        string? slotError = null;
        var price = 80000m;
        PhotographyPackageResponseDto? package = new() { Id = packageId, StudioId = studioId, Status = "Active", DurationHours = 4,
            Services = [new() { Id = serviceId, ServiceName = "Photography" }] };
        var service = new FinalRecommendationValidationService(clock, (selection, today, ct) =>
        {
            reads++;
            cancelDuringRead?.Cancel();
            ct.ThrowIfCancellationRequested();
            if (failRead) throw new InvalidOperationException("PRIVATE database credentials");
            var findings = slotError is null ? Array.Empty<ValidationFinding>() :
                [new ValidationFinding(slotError, "selection", FindingSeverity.Error, "PRIVATE booking 123 customer 456")];
            return Task.FromResult<(PhotographyPackageResponseDto?, RecommendationCheck)>((package, new RecommendationCheck(new(slotError is null ? ValidationOutcome.Pass : ValidationOutcome.Fail,
                findings, clock.GetUtcNow()), new PackagePriceCalculationResponseDto { PackageId = packageId, BasePrice = price, FinalPrice = price })));
        });
        var controller = new RecommendationValidationController(service)
        { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
        RecommendationSelection Selection(Guid? studio = null, Guid? packageReference = null) => new()
        { StudioId = studio ?? studioId, PackageId = packageReference ?? packageId, Date = day, StartTime = new(8, 0), EndTime = new(12, 0) };
        FinalValidationRequest Request(decimal budget = 100000, RecommendationSelection? selected = null,
            RecommendationSelection? previous = null) => new()
        {
            Requirements = new() { PhotographyType = "Wedding", Location = "Jaffna", MaximumBudget = budget, CoverageHours = 4,
                EarliestDate = day, LatestDate = day, RequestedServices = ["Photography"], Notes = "PRIVATE customer notes" },
            Selection = selected ?? Selection(),
            PriorEvidence = new() { Selection = previous ?? Selection(), QuotedFinalPrice = 80000, PackageDurationHours = 4,
                IncludedServices = [new(serviceId, "Photography")], CheckedAtUtc = clock.GetUtcNow(), SlotWasAvailable = true }
        };
        async Task<ObjectResult> Call(FinalValidationRequest? request = null, Guid? studio = null, Guid? packageReference = null) =>
            (ObjectResult)(await controller.ValidateRecommendation(studio ?? studioId, packageReference ?? packageId,
                request ?? Request(), default)).Result!;
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var result = await Call();
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.Pass }, "valid Pass 200");
        var evidence = (FinalValidationResult)result.Value!;
        Check(evidence.Current!.Selection.StudioId == studioId && evidence.Current.Selection.PackageId == packageId, "route references retained");
        Check(evidence.Current.Pricing!.FinalPrice == 80000 && !evidence.IsReservation, "current sanitized evidence");
        result = await Call(Request(budget: 70000));
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.Fail }, "domain Fail 200");
        price = 90000;
        result = await Call();
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.RevalidationRequired }, "price change 200");
        price = 80000;
        foreach (var error in new[] { "Unavailable", "Conflict" })
        {
            slotError = error; result = await Call();
            evidence = (FinalValidationResult)result.Value!;
            Check(result.StatusCode == 200 && evidence.Classification == FinalValidationClassification.RevalidationRequired, "slot domain result " + error);
            var json = JsonSerializer.Serialize(evidence, options);
            Check(!json.Contains("PRIVATE") && !json.Contains("customer", StringComparison.OrdinalIgnoreCase) && !json.Contains("bookingId") && !json.Contains("stack"), "no private conflict details");
            Check(json.Contains("\"isReservation\":false"), "no reservation on conflict");
        }
        slotError = null;
        var saved = package;
        package = null; result = await Call();
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.RevalidationRequired }, "missing public package remains domain result");
        package = saved; package!.Status = "Inactive"; result = await Call();
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.RevalidationRequired }, "inactive domain result");
        package.Status = "Active"; package.StudioId = Guid.NewGuid(); result = await Call();
        Check(result.StatusCode == 200 && result.Value is FinalValidationResult { Classification: FinalValidationClassification.Fail }, "wrong studio relationship domain result");
        package.StudioId = studioId;
        var beforeReads = reads;
        foreach (var request in new[] { Request(selected: Selection(studio: Guid.NewGuid())), Request(selected: Selection(packageReference: Guid.NewGuid())),
            Request(previous: Selection(studio: Guid.NewGuid())), Request(previous: Selection(packageReference: Guid.NewGuid())) })
            Check((await Call(request)).StatusCode == 400, "mismatched body cannot override route");
        Check(reads == beforeReads, "mismatched IDs rejected before service IO");
        Check((await Call(studio: Guid.Empty)).StatusCode == 400 && (await Call(packageReference: Guid.Empty)).StatusCode == 400, "empty route UUIDs");
        Check(((ObjectResult)(await controller.ValidateRecommendation(studioId, packageId, null!, default)).Result!).StatusCode == 400, "missing body");
        Check((await Call(new() { Requirements = null!, Selection = Selection(), PriorEvidence = null! })).StatusCode == 400, "missing nested body");
        foreach (var field in new[] { "studioId", "packageId", "request", "Requirements.EarliestDate" })
        {
            controller.ModelState.AddModelError(field, "PRIVATE malformed input");
            result = await Call();
            Check(result.StatusCode == 400 && !JsonSerializer.Serialize(result.Value).Contains("PRIVATE"), "model binding error safely rejected: " + field);
            controller.ModelState.Clear();
        }
        Check(reads == beforeReads, "all structural errors before reads");
        var action = typeof(RecommendationValidationController).GetMethod(nameof(RecommendationValidationController.ValidateRecommendation))!;
        var route = typeof(RecommendationValidationController).GetCustomAttribute<RouteAttribute>()!.Template;
        Check(route == "api/public/studios/{studioId}/packages/{packageId}/validate-recommendation" && !route.Contains(":guid"), "fixed route allows malformed IDs to reach 400 binding");
        Check(typeof(RecommendationValidationController).GetCustomAttribute<ApiControllerAttribute>() is not null &&
            typeof(RecommendationValidationController).GetCustomAttribute<AllowAnonymousAttribute>() is not null && action.GetCustomAttribute<HttpPostAttribute>() is not null, "anonymous POST with automatic model validation");
        foreach (var name in new[] { "studioId", "packageId" })
            Check(action.GetParameters().Single(p => p.Name == name) is { ParameterType: var type } parameter && type == typeof(Guid) &&
                parameter.GetCustomAttribute<FromRouteAttribute>() is not null, "UUID route binding: " + name);
        foreach (var body in new[] { "not JSON", "{}", "{\"requirements\":42}", "{\"unexpected\":true}" })
        {
            try { JsonSerializer.Deserialize<FinalValidationRequest>(body, options); Check(false, "malformed JSON"); }
            catch (JsonException) { Check(true, "malformed JSON rejected by input serializer"); }
        }
        var input = Request(); var before = JsonSerializer.Serialize(input);
        await Call(input);
        Check(before == JsonSerializer.Serialize(input), "input unchanged");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await controller.ValidateRecommendation(studioId, packageId, input, cancelled.Token); Check(false, "cancelled"); }
        catch (OperationCanceledException) { Check(true, "cancellation propagates"); }
        using (var inFlight = new CancellationTokenSource())
        {
            cancelDuringRead = inFlight;
            try { await controller.ValidateRecommendation(studioId, packageId, input, inFlight.Token); Check(false, "in-flight cancellation"); }
            catch (OperationCanceledException error) { Check(error.CancellationToken == inFlight.Token, "in-flight cancellation token propagates"); }
            finally { cancelDuringRead = null; }
        }
        clock.Throw = true;
        result = await Call(input);
        Check(result.StatusCode == 500 && result.Value is ProblemDetails { Title: "Unable to validate the recommendation." }, "unexpected exception fixed 500");
        Check(!JsonSerializer.Serialize(result.Value).Contains("PRIVATE") && !JsonSerializer.Serialize(result.Value).Contains("InvalidOperationException"), "exception text hidden");
        clock.Throw = false; failRead = true;
        result = await Call();
        Check(result.StatusCode == 500 && result.Value is ProblemDetails, "operational service failure is transport 500");
        Check(typeof(RecommendationValidationController).GetConstructors().Single().GetParameters().Single().ParameterType == typeof(FinalRecommendationValidationService),
            "controller has only read-only validator dependency; no booking/workflow/approval service");

        // Exercise the real routing, JSON formatter, recursive model validation and filters.
        // Only the read callback is registered: no database, booking, workflow or approval
        // writer can be resolved in this host. No production startup/seeding is executed.
        failRead = false;
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Services.AddControllers().AddApplicationPart(typeof(RecommendationValidationController).Assembly);
        builder.Services.AddSingleton(service);
        await using var app = builder.Build();
        app.MapControllers();
        await app.StartAsync();
        try
        {
            using var client = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
            var path = $"/api/public/studios/{studioId}/packages/{packageId}/validate-recommendation";
            var validBody = JsonSerializer.Serialize(Request(), options);
            async Task<string> Post(string body, HttpStatusCode expected, string? url = null)
            {
                using var response = await client.PostAsync(url ?? path, new StringContent(body, Encoding.UTF8, "application/json"));
                var json = await response.Content.ReadAsStringAsync();
                Check(response.StatusCode == expected, "HTTP status " + expected);
                Check(!json.Contains("PRIVATE") && !json.Contains("stackTrace", StringComparison.OrdinalIgnoreCase) &&
                    !json.Contains("InvalidOperationException"), "HTTP response sanitized");
                if (expected == HttpStatusCode.OK)
                    Check(JsonNode.Parse(json)!["isReservation"]!.GetValue<bool>() == false, "HTTP never reserves");
                return json;
            }
            async Task Domain(string body, string classification)
            {
                var json = JsonNode.Parse(await Post(body, HttpStatusCode.OK))!;
                Check(json["classification"]!.GetValue<string>() == classification, "HTTP domain " + classification);
                Check(json["checkedAtUtc"] is not null && json["evidenceExpiresAtUtc"] is not null &&
                    json["timeZoneId"]!.GetValue<string>() == "Asia/Colombo", "HTTP freshness and timezone");
            }
            await Domain(validBody, "Pass");
            await Domain(JsonSerializer.Serialize(Request(budget: 70000), options), "Fail");
            price = 90000; await Domain(validBody, "RevalidationRequired"); price = 80000;
            slotError = "Conflict";
            var conflict = await Post(validBody, HttpStatusCode.OK);
            Check(!conflict.Contains("bookingId", StringComparison.OrdinalIgnoreCase) &&
                !conflict.Contains("customer", StringComparison.OrdinalIgnoreCase), "HTTP conflict contains no private identities");
            slotError = null;
            package = null; await Domain(validBody, "RevalidationRequired"); package = saved;
            package!.Status = "Inactive"; await Domain(validBody, "RevalidationRequired"); package.Status = "Active";
            package.StudioId = Guid.NewGuid(); await Domain(validBody, "Fail"); package.StudioId = studioId;

            beforeReads = reads;
            foreach (var invalidBody in new[] { "", "null", "not JSON PRIVATE", "{}", "{\"requirements\":42}", "{\"unexpected\":true}" })
                await Post(invalidBody, HttpStatusCode.BadRequest);
            await Post(validBody, HttpStatusCode.BadRequest, path.Replace(studioId.ToString(), "PRIVATE-invalid-uuid"));
            await Post(validBody, HttpStatusCode.BadRequest, path.Replace(packageId.ToString(), "PRIVATE-invalid-uuid"));
            foreach (var key in new[] { "selection", "priorEvidence" })
            foreach (var id in new[] { "studioId", "packageId" })
            {
                var body = JsonNode.Parse(validBody)!;
                var selectionNode = key == "selection" ? body[key]! : body[key]!["selection"]!;
                selectionNode[id] = Guid.NewGuid().ToString();
                await Post(body.ToJsonString(), HttpStatusCode.BadRequest);
                selectionNode[id] = "PRIVATE-invalid-uuid";
                await Post(body.ToJsonString(), HttpStatusCode.BadRequest);
            }
            foreach (var (section, field, value) in new (string, string, JsonNode?)[]
            {
                ("requirements", "coverageHours", JsonValue.Create(-1)),
                ("requirements", "requestedServices", null),
                ("selection", "customization", null),
                ("selection", "endTime", JsonValue.Create("07:00:00")),
                ("priorEvidence", "quotedFinalPrice", JsonValue.Create(-1)),
                ("priorEvidence", "packageDurationHours", JsonValue.Create(0))
            })
            {
                var body = JsonNode.Parse(validBody)!;
                body[section]![field] = value;
                await Post(body.ToJsonString(), HttpStatusCode.BadRequest);
            }
            Check(reads == beforeReads, "HTTP invalid structures and route mismatches do not reach reads");
            clock.Throw = true;
            var failure = JsonNode.Parse(await Post(validBody, HttpStatusCode.InternalServerError))!;
            Check(failure["title"]!.GetValue<string>() == "Unable to validate the recommendation." && failure["detail"] is null,
                "HTTP fixed problem response");
            clock.Throw = false; failRead = true;
            await Post(validBody, HttpStatusCode.InternalServerError);
        }
        finally { await app.StopAsync(); }
        return count;
    }
}
