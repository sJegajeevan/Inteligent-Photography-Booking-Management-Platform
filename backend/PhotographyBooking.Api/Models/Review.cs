namespace PhotographyBooking.Api.Models;

public class Review
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int BookingId { get; set; }
    public int CustomerId { get; set; }
    public Guid StudioId { get; set; }
    public int Rating { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Booking Booking { get; set; } = null!;
    public User Customer { get; set; } = null!;
    public Studio Studio { get; set; } = null!;
}
