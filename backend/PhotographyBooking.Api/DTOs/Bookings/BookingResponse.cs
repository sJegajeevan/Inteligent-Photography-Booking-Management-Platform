using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class BookingResponse
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public int StudioId { get; set; }
    public int PackageId { get; set; }
    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }
    public string Location { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public BookingStatus Status { get; set; }
    public decimal TotalPrice { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
