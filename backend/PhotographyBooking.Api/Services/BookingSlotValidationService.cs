using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public enum SlotValidationCode { Available, InvalidTime, StudioNotFound, Unavailable, Duplicate, Conflict }
public sealed record SlotValidationResult(SlotValidationCode Code, string? Error = null)
{
    public bool IsAvailable => Code == SlotValidationCode.Available;
}

/// <summary>Read-only point-in-time checks. Never reserves a slot or changes a booking.</summary>
public sealed class BookingSlotValidationService(ApplicationDbContext db)
{
    public async Task<SlotValidationResult> CheckAsync(Guid studioId, DateOnly date,
        TimeOnly start, TimeOnly end, DateOnly today, CancellationToken ct = default)
    {
        var error = BookingSlotRules.ValidateTime(date, start, end, today);
        if (error is not null) return new(SlotValidationCode.InvalidTime, error);
        if (!await db.Studios.AnyAsync(s => s.Id == studioId, ct))
            return new(SlotValidationCode.StudioNotFound, "The selected studio does not exist.");
        var slot = await db.StudioAvailabilities.AsNoTracking()
            .SingleOrDefaultAsync(s => s.StudioId == studioId && s.Date == date, ct);
        return await CheckAvailabilityAndConflictsAsync(studioId, date, start, end, slot, null, ct);
    }

    // Existing booking writes call this after acquiring their studio and availability locks.
    // Do not fetch an unlocked availability snapshot in place of the supplied locked row.
    internal async Task<SlotValidationResult> CheckAvailabilityAndConflictsAsync(Guid studioId, DateOnly date,
        TimeOnly start, TimeOnly end, StudioAvailability? slot, int? authenticatedCustomerId,
        CancellationToken ct = default)
    {
        if (slot?.StudioId != studioId || slot.Date != date || !BookingSlotRules.FitsAvailability(slot, start, end))
            return new(SlotValidationCode.Unavailable,
                "The selected date and time are no longer available. Please select an available studio time interval.");
        var conflicts = db.Bookings.AsNoTracking().Where(BookingSlotRules.ConflictsWith(studioId, date, start, end));
        if (authenticatedCustomerId.HasValue && await conflicts.AnyAsync(b => b.CustomerId == authenticatedCustomerId.Value &&
                b.StartTime == start && b.EndTime == end, ct))
            return new(SlotValidationCode.Duplicate,
                "You already have an active booking for this studio and time. Check My Bookings before submitting again.");
        if (await conflicts.AnyAsync(ct))
            return new(SlotValidationCode.Conflict,
                "This studio already has a booking overlapping the selected time. Please choose another time.");
        return new(SlotValidationCode.Available);
    }
}
