namespace PhotographyBooking.Api.DTOs.Customers;

public class StudioCustomerDetailResponse
{
    public int CustomerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int TotalBookings { get; set; }
    public int CompletedBookings { get; set; }
    public int ActiveBookings { get; set; }
    public IReadOnlyList<StudioCustomerBookingResponse> Bookings { get; set; } = [];
}

public class StudioCustomerBookingResponse
{
    public int BookingId { get; set; }
    public string PackageName { get; set; } = string.Empty;
    public DateOnly BookingDate { get; set; }
    public string Status { get; set; } = string.Empty;
    public decimal TotalPrice { get; set; }
    public DateTime CreatedAt { get; set; }
}
