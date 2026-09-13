using System.ComponentModel.DataAnnotations;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class UpdateBookingStatusRequest
{
    [EnumDataType(typeof(BookingStatus))]
    public BookingStatus NewStatus { get; set; }

    [Required]
    [MaxLength(200)]
    public string ChangedBy { get; set; } = string.Empty;

    [MaxLength(1_000)]
    public string? Reason { get; set; }
}
