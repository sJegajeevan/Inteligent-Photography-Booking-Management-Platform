namespace PhotographyBooking.Api.Services;

public static class BookingCompletionRules
{
    // Booking date/time fields are wall-clock values in the scheduling business zone,
    // not UTC and not the API host's local timezone.
    private static readonly TimeZoneInfo BusinessZone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Colombo");

    public static bool HasShootEnded(DateOnly bookingDate, TimeOnly endTime, DateTimeOffset now)
    {
        var localEnd = bookingDate.ToDateTime(endTime, DateTimeKind.Unspecified);
        var utcEnd = TimeZoneInfo.ConvertTimeToUtc(localEnd, BusinessZone);
        return now.UtcDateTime > utcEnd;
    }
}
