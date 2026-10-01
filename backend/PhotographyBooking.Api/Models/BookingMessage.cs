using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.Models;

public class BookingMessage
{
    public int Id { get; set; }

    public int BookingId { get; set; }

    public int SenderUserId { get; set; }

    [Required]
    [MaxLength(1000)]
    public string Message { get; set; } = string.Empty;

    public DateTime SentAt { get; set; } = DateTime.UtcNow;

    public Booking Booking { get; set; } = null!;

    public User SenderUser { get; set; } = null!;
}