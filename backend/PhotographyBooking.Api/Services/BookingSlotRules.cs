using System.Linq.Expressions;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

/// <summary>Shared deterministic rules; dates use the caller's authoritative business date.</summary>
public static class BookingSlotRules
{
    public static string? ValidateBookingTotal(decimal total) => total <= 0 || total > 9999999999999999.99m
        ? "The calculated booking total is outside the supported range." : null;

    public static string? ValidateTime(DateOnly date, TimeOnly start, TimeOnly end, DateOnly today)
    {
        if (date < today) return "Booking date cannot be in the past.";
        if (start >= end) return "Start time must be before end time.";
        return null;
    }

    public static bool FitsAvailability(StudioAvailability? slot, TimeOnly start, TimeOnly end) =>
        start < end && slot is { IsAvailable: true, StartTime: not null, EndTime: not null } &&
        slot.StartTime < slot.EndTime && start >= slot.StartTime && end <= slot.EndTime;

    // Keep this as an expression so the exact same predicate runs in PostgreSQL and unit tests.
    public static Expression<Func<Booking, bool>> ConflictsWith(Guid studioId, DateOnly date, TimeOnly start, TimeOnly end) =>
        booking => booking.StudioId == studioId && booking.BookingDate == date &&
            booking.Status != BookingStatus.Cancelled && booking.Status != BookingStatus.Rejected &&
            booking.Status != BookingStatus.Completed && booking.StartTime < end && start < booking.EndTime;

    public static bool FitsPackageDuration(decimal durationHours, int extraHours, TimeOnly start, TimeOnly end) =>
        durationHours > 0 && extraHours >= 0 && start < end &&
        (decimal)(end - start).TotalHours <= durationHours + extraHours;
}
