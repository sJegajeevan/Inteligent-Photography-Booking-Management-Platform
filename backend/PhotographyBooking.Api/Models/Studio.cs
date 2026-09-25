using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.Models;

public class Studio : IValidatableObject
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int UserId { get; set; }
    public string StudioName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    // Unknown coordinates remain null; never substitute (0, 0).
    [Range(typeof(decimal), "-90", "90")]
    public decimal? Latitude { get; set; }
    [Range(typeof(decimal), "-180", "180")]
    public decimal? Longitude { get; set; }
    public string ContactNumber { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int ExperienceYears { get; set; }
    public string PhotographyTypes { get; set; } = string.Empty;
    public decimal StartingPrice { get; set; }
    public string LogoUrl { get; set; } = string.Empty;
    public string CoverPhotoUrl { get; set; } = string.Empty;
    public User User { get; set; } = null!;

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Latitude.HasValue != Longitude.HasValue)
            yield return new ValidationResult("Studio latitude and longitude must be supplied together.",
                [nameof(Latitude), nameof(Longitude)]);
    }
}
