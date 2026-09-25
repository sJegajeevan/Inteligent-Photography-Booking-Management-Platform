using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class SchedulingChecks
{
    private sealed class Clock : TimeProvider
    {
        // 09:00 in Colombo, regardless of the machine's timezone.
        public DateTimeOffset UtcNow { get; set; } = new(2026, 9, 21, 3, 30, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }

    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool condition, string name)
        { if (!condition) throw new Exception("FAILED scheduling: " + name); count++; }
        var day = new DateOnly(2026, 9, 22);
        var studio = Guid.NewGuid();
        var packageId = Guid.NewGuid();
        PhotographyPackageResponseDto? package = new() { Id = packageId, StudioId = studio, Status = "Active", DurationHours = 2 };
        List<StudioAvailability> windows = [];
        List<Booking> bookings = [];
        var validations = 0;
        var reads = 0;
        var rejectValidation = false;
        StudioAvailability Window(DateOnly date, int start = 8, int end = 18) => new()
        { StudioId = studio, Date = date, IsAvailable = true, StartTime = new(start, 0), EndTime = new(end, 0) };
        Booking Busy(int start, int end, BookingStatus status = BookingStatus.Confirmed, DateOnly? date = null) => new()
        { Id = 123, CustomerId = 456, Notes = "PRIVATE", StudioId = studio, BookingDate = date ?? day,
            StartTime = new(start, 0), EndTime = new(end, 0), Status = status };
        SchedulingCandidateRequestDto Request(decimal coverage = 2, int extra = 0, DateOnly? first = null,
            DateOnly? last = null, TimeOnly? start = null, TimeOnly? end = null, string zone = "Asia/Colombo",
            List<Guid>? addons = null, int photographers = 0) => new()
        {
            EarliestDate = first ?? day, LatestDate = last ?? first ?? day, CoverageHours = coverage,
            PreferredStartTime = start, PreferredEndTime = end, TimeZoneId = zone,
            Customization = new() { ExtraHours = extra, SelectedAddonIds = addons ?? [], AdditionalPhotographers = photographers }
        };
        bool Valid(SchedulingCandidateRequestDto request) => Validator.TryValidateObject(request, new(request), [], true);
        var clock = new Clock();
        var service = new SchedulingCandidateService(clock,
            (_, _, _) => { reads++; return Task.FromResult<PhotographyPackageResponseDto?>(package); },
            (id, first, last, _) => { reads++; return Task.FromResult(windows.Where(w => w.StudioId == id && w.Date >= first && w.Date <= last).ToList()); },
            (id, date, start, end, _) => {
                reads++;
                return Task.FromResult(bookings.Where(BookingSlotRules.ConflictsWith(id, date, start, end).Compile())
                    .Select(b => new SchedulingCandidateService.Interval(b.StartTime, b.EndTime)).ToList());
            },
            (id, date, start, end, today, _) => {
                validations++;
                var window = windows.SingleOrDefault(w => w.StudioId == id && w.Date == date);
                var available = !rejectValidation && BookingSlotRules.ValidateTime(date, start, end, today) is null &&
                    BookingSlotRules.FitsAvailability(window, start, end) &&
                    !bookings.Any(BookingSlotRules.ConflictsWith(id, date, start, end).Compile());
                return Task.FromResult(new SlotValidationResult(available ? SlotValidationCode.Available : SlotValidationCode.Conflict));
            });
        async Task<SchedulingCandidateResponseDto> Discover(SchedulingCandidateRequestDto? request = null)
        {
            var result = await service.DiscoverAsync(studio, packageId, request ?? Request());
            Check(result.ErrorCode is null && result.Response is not null, "successful read");
            return result.Response!;
        }
        windows = [Window(day)];
        var response = await Discover();
        Check(response.Candidates.Single().StartTime == new TimeOnly(8, 0) && response.Candidates[0].EndTime == new TimeOnly(10, 0), "equal coverage; earliest/no preference");
        Check(validations == 1, "every emitted candidate verified");
        Check(!response.IsReservation && response.TimeZoneId == "Asia/Colombo", "point-in-time contract");
        Check((await Discover()).Candidates[0].SlotId != response.Candidates[0].SlotId, "opaque ephemeral IDs");
        response = await Discover(Request(3, 1));
        Check(response.RequiredDurationHours == 3 && response.ExtraHours == 1 && response.Candidates[0].EndTime == new TimeOnly(11, 0), "extra hours");
        Check((await service.DiscoverAsync(studio, packageId, Request(3))).ErrorCode == "invalid_scheduling_input", "insufficient purchased coverage");
        package!.DurationHours = 1.125m;
        response = await Discover(Request(1));
        Check(response.Candidates[0].EndTime == new TimeOnly(9, 7, 30), "fractional duration never rounded down");
        package.DurationHours = 2;
        response = await Discover(Request(start: new(10, 0), end: new(13, 0)));
        Check(response.Candidates[0].StartTime == new TimeOnly(10, 0), "preferred window");
        Check((await Discover(Request(start: new(10, 0), end: new(11, 0)))).Candidates.Count == 0, "short preferred window");
        windows[0].IsAvailable = false;
        Check((await Discover()).Candidates.Count == 0, "unavailable date");
        windows = [Window(day, 8, 9)];
        Check((await Discover()).Candidates.Count == 0, "short availability");
        windows = [];
        Check((await Discover()).Candidates.Count == 0, "missing availability");
        windows = [Window(day, 8, 10)];
        foreach (var status in Enum.GetValues<BookingStatus>())
        {
            bookings = [Busy(8, 10, status)];
            var blocking = status is not (BookingStatus.Cancelled or BookingStatus.Rejected or BookingStatus.Completed);
            Check((await Discover()).Candidates.Count == (blocking ? 0 : 1), "status " + status);
        }
        foreach (var (start, end) in new[] { (7, 9), (9, 11), (7, 11), (8, 10), (8, 9) })
        {
            bookings = [Busy(start, end)];
            Check((await Discover()).Candidates.Count == 0, "partial/exact/contained overlap " + start + "-" + end);
        }
        bookings = [Busy(6, 8), Busy(10, 12)];
        Check((await Discover()).Candidates.Count == 1, "adjacency allowed");
        windows = [Window(day, 8, 18)];
        bookings = [Busy(12, 14), Busy(10, 13), Busy(11, 12)];
        response = await Discover();
        Check(response.Candidates.Count == 2 && response.Candidates[1].StartTime == new TimeOnly(14, 0), "overlapping busy intervals merged by cursor");
        rejectValidation = true;
        Check((await Discover()).Candidates.Count == 0, "authoritative validator rejection never bypassed");
        rejectValidation = false;
        bookings = [];
        windows = [Window(day), Window(day.AddDays(1)), Window(day.AddDays(2))];
        Check((await Discover(Request(last: day.AddDays(1)))).Candidates.Count == 2, "inclusive date range");
        windows = [Window(day.AddDays(-2)), Window(day.AddDays(-1)), Window(day)];
        response = await Discover(Request(first: day.AddDays(-2), last: day));
        Check(response.Candidates.Count == 2 && response.Candidates[0].Date == day.AddDays(-1), "past dates excluded");
        Check(response.Candidates[0].StartTime == new TimeOnly(9, 0), "UTC clock converted to Colombo; elapsed time excluded");
        Check((await Discover(Request(first: day.AddDays(-2)))).Candidates.Count == 0, "entire past range empty");
        clock.UtcNow = new(2026, 9, 20, 20, 0, 0, TimeSpan.Zero);
        response = await Discover(Request(first: day.AddDays(-2), last: day));
        Check(response.Candidates[0].Date == day.AddDays(-1), "Colombo calendar date differs from UTC date");
        clock.UtcNow = new(2026, 9, 21, 3, 30, 0, TimeSpan.Zero);
        windows = [Window(day)];
        response = await Discover(Request(1));
        Check(response.Candidates[0].EndTime == new TimeOnly(10, 0), "full purchased duration even when coverage is shorter");
        var input = Request(extra: 1);
        var originalInput = JsonSerializer.Serialize(input);
        await Discover(input);
        Check(JsonSerializer.Serialize(input) == originalInput, "customization never silently changed");
        windows = [Window(day, 22, 23)];
        Check((await Discover()).Candidates.Count == 0, "no midnight wrap");
        Check(!Valid(Request(zone: "UTC")), "unsupported timezone");
        Check(Valid(Request(last: day.AddDays(30))) && !Valid(Request(last: day.AddDays(31))), "31 inclusive days limit");
        Check(!Valid(Request(last: day.AddDays(-1))), "inverted dates");
        Check(!Valid(Request(start: new(8, 0))) && !Valid(Request(start: new(9, 0), end: new(8, 0))), "invalid preferred pair");
        Check(!Valid(Request(0)) && !Valid(Request(25)) && !Valid(Request(extra: -1)), "coverage/customization bounds");
        Check(!Valid(Request(photographers: -1)) && !Valid(Request(photographers: 1)), "photographer policy");
        Check(!Valid(Request(addons: [packageId, packageId])) && !Valid(Request(addons: [packageId])), "duplicate/unsupported addons");
        Check(!Valid(new() { EarliestDate = day, LatestDate = day, CoverageHours = 2, Customization = null! }), "null customization");
        Check(!Valid(new() { EarliestDate = day, LatestDate = day, CoverageHours = 2, Customization = new() { SelectedAddonIds = null! } }), "null addon list");
        var oldReads = reads;
        Check((await service.DiscoverAsync(studio, packageId, Request(zone: "UTC"))).ErrorCode == "invalid_scheduling_input" && reads == oldReads, "invalid input before IO");
        package.Status = "Inactive";
        Check((await service.DiscoverAsync(studio, packageId, Request())).ErrorCode == "package_unavailable", "inactive package");
        package.Status = "Active"; package.StudioId = Guid.NewGuid();
        Check((await service.DiscoverAsync(studio, packageId, Request())).ErrorCode == "package_unavailable", "wrong studio");
        package.StudioId = studio; package.Id = Guid.NewGuid();
        Check((await service.DiscoverAsync(studio, packageId, Request())).ErrorCode == "package_unavailable", "wrong package ID");
        package.Id = packageId;
        var savedPackage = package; package = null;
        Check((await service.DiscoverAsync(studio, packageId, Request())).ErrorCode == "package_unavailable", "missing package");
        package = savedPackage;
        windows = Enumerable.Range(0, 26).Select(i => Window(day.AddDays(i))).ToList();
        bookings = windows.Select(w => Busy(10, 12, date: w.Date)).ToList();
        response = await Discover(Request(last: day.AddDays(25)));
        Check(response.Candidates.Count == 50 && response.Truncated, "51st valid candidate proves truncation");
        response = await Discover(Request(last: day.AddDays(24)));
        Check(response.Candidates.Count == 50 && !response.Truncated, "exact limit not truncated");
        Check(response.Candidates.Select(c => c.SlotId).Distinct().Count() == 50 && response.Candidates.All(c => c.EvidenceIds.Count == 1), "unique IDs/evidence");
        var json = JsonSerializer.Serialize(response, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check(!json.Contains("booking", StringComparison.OrdinalIgnoreCase) && !json.Contains("customer", StringComparison.OrdinalIgnoreCase) &&
            !json.Contains("notes", StringComparison.OrdinalIgnoreCase) && !json.Contains("PRIVATE") && json.Contains("\"isReservation\":false"), "private fields absent");
        var before = JsonSerializer.Serialize(bookings);
        await Discover(Request(last: day.AddDays(24)));
        Check(before == JsonSerializer.Serialize(bookings), "input bookings unchanged; only read delegates supplied");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await service.DiscoverAsync(studio, packageId, Request(), cancelled.Token); Check(false, "cancellation"); }
        catch (OperationCanceledException) { Check(true, "cancellation propagated"); }
        return count;
    }
}
