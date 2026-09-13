using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class BookingStatusHistoryResponse
{
    public int Id { get; set; }
    public int BookingId { get; set; }
    public BookingStatus? OldStatus { get; set; }
    public BookingStatus NewStatus { get; set; }
    public string ChangedBy { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public DateTime CreatedAt { get; set; }
}
