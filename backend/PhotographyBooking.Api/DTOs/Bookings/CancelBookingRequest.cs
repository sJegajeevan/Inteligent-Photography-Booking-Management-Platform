using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class CancelBookingRequest
{
    [Required]
    [MaxLength(200)]
    public string ChangedBy { get; set; } = string.Empty;

    [MaxLength(1_000)]
    public string? Reason { get; set; }
}
