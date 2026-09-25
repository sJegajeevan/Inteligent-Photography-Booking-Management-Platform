using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Studio;

public class UpdateStudioDto : IValidatableObject
{
    [Range(typeof(decimal), "-90", "90")] public decimal? Latitude { get; set; }
    [Range(typeof(decimal), "-180", "180")] public decimal? Longitude { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Latitude.HasValue != Longitude.HasValue)
            yield return new ValidationResult("Supply both latitude and longitude, or leave both empty.",
                [nameof(Latitude), nameof(Longitude)]);
    }
    [Required, StringLength(120, MinimumLength = 2)] public string StudioName { get; set; } = string.Empty;
    [Required, StringLength(1000, MinimumLength = 10)] public string Description { get; set; } = string.Empty;
    [Required, StringLength(160, MinimumLength = 2)] public string Location { get; set; } = string.Empty;
    [Required, StringLength(240, MinimumLength = 5)] public string Address { get; set; } = string.Empty;
    [Required, StringLength(30, MinimumLength = 7)] public string ContactNumber { get; set; } = string.Empty;
    [Required, EmailAddress, StringLength(254)] public string Email { get; set; } = string.Empty;
    [Range(0, 100)] public int ExperienceYears { get; set; }
    [Required, StringLength(500, MinimumLength = 2)] public string PhotographyTypes { get; set; } = string.Empty;
    [Range(typeof(decimal), "0", "9999999999.99")] public decimal StartingPrice { get; set; }
    public IFormFile? LogoImage { get; set; }
    public IFormFile? CoverImage { get; set; }
}
