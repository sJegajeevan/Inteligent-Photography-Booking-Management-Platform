using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Reviews;

public class CreateReviewRequest
{
    [Range(1, int.MaxValue)]
    public int BookingId { get; set; }

    [Range(1, 5)]
    public int Rating { get; set; }

    [MaxLength(2000)]
    public string? Comment { get; set; }
}
