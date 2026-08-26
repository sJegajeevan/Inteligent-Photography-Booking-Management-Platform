namespace PhotographyBooking.Api.Models;

public enum BookingStatus
{
    Pending,
    AIRecommended,
    AwaitingApproval,
    Confirmed,
    Rejected,
    Cancelled,
    Rescheduled,
    Completed
}
