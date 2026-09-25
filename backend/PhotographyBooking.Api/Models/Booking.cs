namespace PhotographyBooking.Api.Models;

public class Booking
{
    public int Id { get; set; }

    public int CustomerId { get; set; }
    public Guid StudioId { get; set; }
    public Guid PackageId { get; set; }

    public User Customer { get; set; } = null!;
    public Studio Studio { get; set; } = null!;
    public PhotographyPackage Package { get; set; } = null!;

    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }

    public string Location { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public BookingStatus Status { get; set; } = BookingStatus.Pending;
    public decimal TotalPrice { get; set; }
    // Server-calculated selections and prices at creation; null for legacy bookings.
    // Keep this snapshot unchanged when package prices or add-ons change later.
    public string? PricingSnapshotJson { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    public List<BookingStatusHistory> StatusHistory { get; set; } = [];
    public BookingLocation? BookingLocation { get; set; }
}
