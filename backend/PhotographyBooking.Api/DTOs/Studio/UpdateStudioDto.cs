using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Studio;

public class UpdateStudioDto
{
    [Required, StringLength(120, MinimumLength = 2)] public string StudioName { get; set; } = string.Empty;
    [Required, StringLength(1000, MinimumLength = 10)] public string Description { get; set; } = string.Empty;
    [Required, StringLength(160, MinimumLength = 2)] public string Location { get; set; } = string.Empty;
    [Required, StringLength(240, MinimumLength = 5)] public string Address { get; set; } = string.Empty;
    [Required, StringLength(30, MinimumLength = 7)] public string ContactNumber { get; set; } = string.Empty;
    [Required, EmailAddress, StringLength(254)] public string Email { get; set; } = string.Empty;
    [Range(0, 100)] public int ExperienceYears { get; set; }
    [Required, StringLength(500, MinimumLength = 2)] public string PhotographyTypes { get; set; } = string.Empty;
    [Range(typeof(decimal), "0", "9999999999.99")] public decimal StartingPrice { get; set; }
    [Url, StringLength(2048)] public string LogoUrl { get; set; } = string.Empty;
    [Url, StringLength(2048)] public string CoverPhotoUrl { get; set; } = string.Empty;
}
