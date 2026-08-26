namespace PhotographyBooking.Api.Models;

public class Booking
{
    public int Id { get; set; }

    // These IDs will be connected to the shared Customer, Studio, and Package
    // entities when those modules are available.
    public int CustomerId { get; set; }
    public int StudioId { get; set; }
    public int PackageId { get; set; }

    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }

    public string Location { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public BookingStatus Status { get; set; } = BookingStatus.Pending;
    public decimal TotalPrice { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public List<BookingStatusHistory> StatusHistory { get; set; } = [];
    public BookingLocation? BookingLocation { get; set; }
}
