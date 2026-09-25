namespace PhotographyBooking.Api.Models;

public class Notification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int CustomerId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public int? BookingId { get; set; }
    public bool IsRead { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public User Customer { get; set; } = null!;
    public Booking? Booking { get; set; }
}
