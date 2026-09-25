namespace PhotographyBooking.Api.DTOs.Customers;

public class StudioCustomerResponse
{
    public int CustomerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int TotalBookings { get; set; }
    public DateOnly LatestBookingDate { get; set; }
    public string LatestBookingStatus { get; set; } = string.Empty;
}
