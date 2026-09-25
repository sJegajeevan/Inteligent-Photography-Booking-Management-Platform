using System.Reflection;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Constraints;
using PhotographyBooking.Api.Controllers;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class SchedulingEndpointChecks
{
    private sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2026, 9, 21, 0, 0, 0, TimeSpan.Zero);
    }

    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool condition, string name)
        { if (!condition) throw new Exception("FAILED scheduling endpoint: " + name); count++; }
        var studioId = Guid.NewGuid();
        var packageId = Guid.NewGuid();
        var date = new DateOnly(2026, 9, 22);
        PhotographyPackageResponseDto? package = new() { Id = packageId, StudioId = studioId, Status = "Active", DurationHours = 2 };
        var empty = false;
        var fail = false;
        var reads = 0;
        var service = new SchedulingCandidateService(new Clock(),
            (_, _, ct) => {
                reads++; ct.ThrowIfCancellationRequested();
                if (fail) throw new InvalidOperationException("PRIVATE booking 123 customer 456 secret connection string");
                return Task.FromResult<PhotographyPackageResponseDto?>(package);
            },
            (studio, first, last, _) => Task.FromResult(empty ? new List<StudioAvailability>() :
                Enumerable.Range(0, last.DayNumber - first.DayNumber + 1).Select(i => new StudioAvailability
                { StudioId = studio, Date = first.AddDays(i), IsAvailable = true, StartTime = new(8, 0), EndTime = new(18, 0), Notes = "PRIVATE" }).ToList()),
            (_, _, _, _, _) => Task.FromResult(new List<SchedulingCandidateService.Interval> { new(new(10, 0), new(12, 0)) }),
            (_, _, _, _, _, _) => Task.FromResult(new SlotValidationResult(SlotValidationCode.Available)));
        // The controller has no usable booking, pricing, or database dependency in these checks.
        var controller = new PublicPackagesController(null!, null!)
        { ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() } };
        SchedulingCandidateRequestDto Request(DateOnly? last = null, string zone = "Asia/Colombo",
            TimeOnly? start = null, TimeOnly? end = null, int extra = 0, int photographers = 0, decimal coverage = 2,
            List<Guid>? addons = null) => new()
        {
            EarliestDate = date, LatestDate = last ?? date, TimeZoneId = zone, CoverageHours = coverage,
            PreferredStartTime = start, PreferredEndTime = end,
            Customization = new() { ExtraHours = extra, AdditionalPhotographers = photographers, SelectedAddonIds = addons ?? [] }
        };
        async Task<ObjectResult> Call(SchedulingCandidateRequestDto? request = null, Guid? studio = null, Guid? id = null) =>
            (ObjectResult)(await controller.AvailableSlots(studio ?? studioId, id ?? packageId, request ?? Request(), service, default)).Result!;
        var result = await Call();
        Check(result.StatusCode == 200 && result.Value is SchedulingCandidateResponseDto, "valid request returns DTO");
        var response = (SchedulingCandidateResponseDto)result.Value!;
        Check(response.Candidates.Count == 2 && !response.IsReservation, "read-only candidate response");
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var json = JsonSerializer.Serialize(response, options);
        var fields = JsonDocument.Parse(json).RootElement.EnumerateObject().Select(p => p.Name).Order().ToArray();
        Check(fields.SequenceEqual(new[] { "studioId", "packageId", "timeZoneId", "packageDurationHours", "extraHours", "requiredDurationHours", "checkedAtUtc", "isReservation", "truncated", "candidates" }.Order()), "only allowed response fields");
        var candidateFields = JsonDocument.Parse(json).RootElement.GetProperty("candidates")[0].EnumerateObject().Select(p => p.Name).Order();
        Check(candidateFields.SequenceEqual(new[] { "slotId", "date", "startTime", "endTime", "evidenceIds" }.Order()), "only allowed candidate fields");
        Check(!json.Contains("PRIVATE") && !json.Contains("booking", StringComparison.OrdinalIgnoreCase) && !json.Contains("customer", StringComparison.OrdinalIgnoreCase), "no private data");
        empty = true;
        result = await Call();
        Check(result.StatusCode == 200 && ((SchedulingCandidateResponseDto)result.Value!).Candidates.Count == 0, "empty success");
        empty = false;
        Check((await Call(studio: Guid.Empty)).StatusCode == 400 && (await Call(id: Guid.Empty)).StatusCode == 400, "empty UUIDs rejected");
        Check((await Call(studio: Guid.NewGuid())).StatusCode == 404, "wrong studio");
        Check((await Call(id: Guid.NewGuid())).StatusCode == 404, "wrong package");
        package!.Status = "Inactive";
        Check((await Call()).StatusCode == 404, "inactive package");
        var saved = package; package = null;
        Check((await Call()).StatusCode == 404, "missing studio/package");
        package = saved; package.Status = "Active";
        foreach (var invalid in new[] { Request(last: date.AddDays(-1)), Request(last: date.AddDays(31)), Request(zone: "UTC"),
            Request(start: new(8, 0)), Request(start: new(10, 0), end: new(8, 0)), Request(extra: -1),
            Request(photographers: 1), Request(addons: [packageId, packageId]), Request(coverage: 0) })
        {
            var beforeReads = reads;
            Check((await Call(invalid)).StatusCode == 400 && reads == beforeReads, "invalid DTO safely rejected before IO");
        }
        Check((await Call(Request(coverage: 3))).StatusCode == 400, "insufficient purchased duration");
        Check(((ObjectResult)(await controller.AvailableSlots(studioId, packageId, null!, service, default)).Result!).StatusCode == 400,
            "null request safely rejected");
        var readsBeforeModelError = reads;
        controller.ModelState.AddModelError("request", "Malformed request body.");
        result = await Call();
        // MVC copies ProblemDetails.Status onto the HTTP response during result execution.
        Check((result.StatusCode ?? (result.Value as ProblemDetails)?.Status) == 400 && reads == readsBeforeModelError,
            "body binding errors rejected without service access");
        controller.ModelState.Clear();
        response = (SchedulingCandidateResponseDto)(await Call(Request(last: date.AddDays(30)))).Value!;
        Check(response.Candidates.Count == 50 && response.Truncated, "controller preserves candidate cap");
        var input = Request();
        var beforeInput = JsonSerializer.Serialize(input);
        await Call(input);
        Check(beforeInput == JsonSerializer.Serialize(input), "input unchanged");
        fail = true;
        result = await Call();
        json = JsonSerializer.Serialize(result.Value, options);
        Check(result.StatusCode == 500 && result.Value is ProblemDetails, "unexpected service failure mapped safely");
        Check(!json.Contains("PRIVATE") && !json.Contains("InvalidOperationException") && !json.Contains("connection string") && !json.Contains("stack", StringComparison.OrdinalIgnoreCase), "exception details hidden");
        fail = false;
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await controller.AvailableSlots(studioId, packageId, Request(), service, cancelled.Token); Check(false, "cancellation"); }
        catch (OperationCanceledException) { Check(true, "request cancellation propagated"); }
        var action = typeof(PublicPackagesController).GetMethod(nameof(PublicPackagesController.AvailableSlots))!;
        Check(action.GetCustomAttribute<HttpPostAttribute>()?.Template == "{packageId:guid}/available-slots" &&
            typeof(PublicPackagesController).GetCustomAttribute<RouteAttribute>()?.Template == "api/public/studios/{studioId:guid}/packages", "exact POST route with UUID constraints");
        Check(action.GetCustomAttribute<AllowAnonymousAttribute>() is not null, "explicit public access");
        Check(typeof(PublicPackagesController).GetCustomAttribute<ApiControllerAttribute>() is not null &&
            action.GetParameters().Single(p => p.Name == "request").GetCustomAttribute<FromBodyAttribute>() is not null, "MVC automatic body/model validation enabled");
        foreach (var key in new[] { "studioId", "packageId" })
            Check(!new GuidRouteConstraint().Match(new DefaultHttpContext(), null, key, new RouteValueDictionary { [key] = "not-a-uuid" }, RouteDirection.IncomingRequest), "malformed UUID cannot match route: " + key);
        // No write-capable dependency is supplied or invoked. Scheduling service only receives read callbacks.
        Check(reads > 0, "endpoint delegates to existing read-only service");
        return count;
    }
}
