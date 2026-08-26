using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class CreateBookingRequest
{
    [Range(1, int.MaxValue)]
    public int CustomerId { get; set; }

    [Range(1, int.MaxValue)]
    public int StudioId { get; set; }

    [Range(1, int.MaxValue)]
    public int PackageId { get; set; }

    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }

    [Required]
    [MaxLength(500)]
    public string Location { get; set; } = string.Empty;

    [MaxLength(1_000)]
    public string? Notes { get; set; }

    [Range(typeof(decimal), "0.01", "9999999999999999.99")]
    public decimal TotalPrice { get; set; }
}
