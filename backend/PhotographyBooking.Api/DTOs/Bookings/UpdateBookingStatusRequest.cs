using System.ComponentModel.DataAnnotations;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class UpdateBookingStatusRequest
{
    [EnumDataType(typeof(BookingStatus))]
    public BookingStatus NewStatus { get; set; }

    [MaxLength(1_000)]
    public string? Reason { get; set; }
}
