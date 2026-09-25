using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public sealed record SchedulingCandidateResult(SchedulingCandidateResponseDto? Response, string? ErrorCode = null);

/// <summary>Read-only bounded sampling. Actual booking creation must retain its locked revalidation.</summary>
public sealed class SchedulingCandidateService
{
    public const int MaximumCandidates = 50;
    private static readonly TimeZoneInfo BusinessZone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Colombo");
    private readonly TimeProvider _clock;
    private readonly Func<Guid, Guid, CancellationToken, Task<PhotographyPackageResponseDto?>> _package;
    private readonly Func<Guid, DateOnly, DateOnly, CancellationToken, Task<List<StudioAvailability>>> _windows;
    private readonly Func<Guid, DateOnly, TimeOnly, TimeOnly, CancellationToken, Task<List<Interval>>> _conflicts;
    private readonly Func<Guid, DateOnly, TimeOnly, TimeOnly, DateOnly, CancellationToken, Task<SlotValidationResult>> _validate;
    internal sealed record Interval(TimeOnly Start, TimeOnly End);

    public SchedulingCandidateService(ApplicationDbContext db, PhotographyPackageService packages,
        BookingSlotValidationService slots, TimeProvider clock) : this(clock,
        async (studio, package, ct) => { ct.ThrowIfCancellationRequested(); return await packages.GetPublicAsync(studio, package); },
        (studio, first, last, ct) => db.StudioAvailabilities.AsNoTracking()
            .Where(a => a.StudioId == studio && a.Date >= first && a.Date <= last).OrderBy(a => a.Date).ToListAsync(ct),
        (studio, date, start, end, ct) => db.Bookings.AsNoTracking()
            .Where(BookingSlotRules.ConflictsWith(studio, date, start, end))
            .OrderBy(b => b.StartTime).ThenBy(b => b.EndTime)
            .Select(b => new Interval(b.StartTime, b.EndTime)).ToListAsync(ct),
        slots.CheckAsync) { }

    // Internal read-only dependency seam keeps checks offline without a database or new mocking packages.
    internal SchedulingCandidateService(TimeProvider clock,
        Func<Guid, Guid, CancellationToken, Task<PhotographyPackageResponseDto?>> package,
        Func<Guid, DateOnly, DateOnly, CancellationToken, Task<List<StudioAvailability>>> windows,
        Func<Guid, DateOnly, TimeOnly, TimeOnly, CancellationToken, Task<List<Interval>>> conflicts,
        Func<Guid, DateOnly, TimeOnly, TimeOnly, DateOnly, CancellationToken, Task<SlotValidationResult>> validate)
    { _clock = clock; _package = package; _windows = windows; _conflicts = conflicts; _validate = validate; }

    public async Task<SchedulingCandidateResult> DiscoverAsync(Guid studioId, Guid packageId,
        SchedulingCandidateRequestDto request, CancellationToken ct = default)
    {
        if (request is null || studioId == Guid.Empty || packageId == Guid.Empty ||
            !Validator.TryValidateObject(request, new ValidationContext(request), [], true))
            return new(null, "invalid_scheduling_input");
        ct.ThrowIfCancellationRequested();
        // Snapshot mutable nested input before awaiting dependencies. Never alter the caller's customization.
        var extraHours = request.Customization.ExtraHours;
        var package = await _package(studioId, packageId, ct);
        if (package is null || package.Id != packageId || package.StudioId != studioId || package.Status != "Active")
            return new(null, "package_unavailable");
        if (package.DurationHours <= 0 || package.DurationHours > 24 || extraHours > 24 ||
            package.DurationHours + extraHours > 24 || package.DurationHours + extraHours < request.CoverageHours)
            return new(null, "invalid_scheduling_input");
        var required = package.DurationHours + extraHours;
        // Decimal arithmetic, rounded UP to .NET time precision: never shorten purchased coverage.
        var durationTicks = (long)decimal.Ceiling(required * TimeSpan.TicksPerHour);
        var now = TimeZoneInfo.ConvertTime(_clock.GetUtcNow(), BusinessZone);
        var today = DateOnly.FromDateTime(now.DateTime);
        var first = request.EarliestDate < today ? today : request.EarliestDate;
        var candidates = new List<SchedulingCandidateDto>();
        var truncated = false;
        if (first <= request.LatestDate)
        {
            var windows = await _windows(studioId, first, request.LatestDate, ct);
            foreach (var window in windows.OrderBy(w => w.Date))
            {
                ct.ThrowIfCancellationRequested();
                if (window.StudioId != studioId || window.Date < first || window.Date > request.LatestDate ||
                    !window.IsAvailable || window.StartTime is null || window.EndTime is null) continue;
                var start = window.StartTime.Value;
                var end = window.EndTime.Value;
                if (request.PreferredStartTime is { } preferredStart && preferredStart > start) start = preferredStart;
                if (request.PreferredEndTime is { } preferredEnd && preferredEnd < end) end = preferredEnd;
                // Refresh the clock per date: queries may cross midnight or consume time today.
                now = TimeZoneInfo.ConvertTime(_clock.GetUtcNow(), BusinessZone);
                var currentDate = DateOnly.FromDateTime(now.DateTime);
                if (window.Date < currentDate) continue;
                if (window.Date == currentDate && TimeOnly.FromDateTime(now.DateTime) > start)
                    start = TimeOnly.FromDateTime(now.DateTime);
                if (!BookingSlotRules.FitsAvailability(window, start, end)) continue;
                var conflicts = await _conflicts(studioId, window.Date, start, end, ct);
                var cursor = start;
                foreach (var busy in conflicts.OrderBy(b => b.Start).ThenBy(b => b.End))
                {
                    if (busy.Start > cursor && await AddGap(cursor, busy.Start < end ? busy.Start : end)) break;
                    if (busy.End > cursor) cursor = busy.End;
                    if (cursor >= end) break;
                }
                if (!truncated && cursor < end) await AddGap(cursor, end);
                if (truncated) break;

                async Task<bool> AddGap(TimeOnly gapStart, TimeOnly gapEnd)
                {
                    ct.ThrowIfCancellationRequested();
                    var checkTime = TimeZoneInfo.ConvertTime(_clock.GetUtcNow(), BusinessZone);
                    var checkDate = DateOnly.FromDateTime(checkTime.DateTime);
                    if (window.Date < checkDate) return false;
                    if (window.Date == checkDate && TimeOnly.FromDateTime(checkTime.DateTime) > gapStart)
                        gapStart = TimeOnly.FromDateTime(checkTime.DateTime);
                    if (gapEnd.Ticks - gapStart.Ticks < durationTicks) return false;
                    var slotEnd = new TimeOnly(gapStart.Ticks + durationTicks);
                    if (!BookingSlotRules.FitsPackageDuration(package.DurationHours, extraHours, gapStart, slotEnd)) return false;
                    var validation = await _validate(studioId, window.Date, gapStart, slotEnd, checkDate, ct);
                    if (!validation.IsAvailable) return false;
                    // Inspect one extra VALID candidate, so truncation never means merely 'limit reached'.
                    if (candidates.Count == MaximumCandidates) { truncated = true; return true; }
                    candidates.Add(new(Guid.NewGuid(), window.Date, gapStart, slotEnd, [Guid.NewGuid().ToString("N")]));
                    return false;
                }
            }
        }
        return new(new(studioId, packageId, "Asia/Colombo", package.DurationHours, extraHours, required,
            _clock.GetUtcNow(), truncated, candidates));
    }
}
