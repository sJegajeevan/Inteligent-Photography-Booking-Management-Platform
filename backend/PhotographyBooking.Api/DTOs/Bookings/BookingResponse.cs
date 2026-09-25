using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class BookingResponse
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public Guid StudioId { get; set; }
    public Guid PackageId { get; set; }
    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }
    public string Location { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public BookingStatus Status { get; set; }
    public decimal TotalPrice { get; set; }
    public PackagePriceCalculationResponseDto? Customization { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
