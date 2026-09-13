namespace PhotographyBooking.Api.Models;

public class BookingStatusHistory
{
    public int Id { get; set; }
    public int BookingId { get; set; }
    public BookingStatus? OldStatus { get; set; }
    public BookingStatus NewStatus { get; set; }
    public string ChangedBy { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Booking? Booking { get; set; }
}
