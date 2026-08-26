namespace PhotographyBooking.Api.Models;

public class BookingLocation
{
    public int Id { get; set; }
    public int BookingId { get; set; }
    public string Address { get; set; } = string.Empty;
    public string City { get; set; } = string.Empty;
    public decimal? Latitude { get; set; }
    public decimal? Longitude { get; set; }
    public string? Notes { get; set; }

    public Booking? Booking { get; set; }
}
