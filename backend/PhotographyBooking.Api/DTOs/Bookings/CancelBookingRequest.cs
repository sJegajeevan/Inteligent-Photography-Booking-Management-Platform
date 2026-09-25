using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class CancelBookingRequest
{
    [MaxLength(1_000)]
    public string? Reason { get; set; }
}
