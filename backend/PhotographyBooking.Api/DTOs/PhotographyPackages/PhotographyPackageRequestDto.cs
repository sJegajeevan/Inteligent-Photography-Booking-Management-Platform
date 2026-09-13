using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.PhotographyPackages;

public class PhotographyPackageRequestDto
{
    [Required, StringLength(160), RegularExpression(@".*\S.*", ErrorMessage = "Package name is required.")]
    public string Name { get; set; } = string.Empty;
    [StringLength(2000)] public string? Description { get; set; }
    [Range(typeof(decimal), "0.01", "9999999999.99", ErrorMessage = "Base price must be greater than zero.")]
    public decimal BasePrice { get; set; }
    [Range(typeof(decimal), "0", "9999999999.99", ErrorMessage = "Extra hour rate cannot be negative.")]
    public decimal ExtraHourRate { get; set; }
    [Range(typeof(decimal), "0", "9999999999.99", ErrorMessage = "Additional photographer rate cannot be negative.")]
    public decimal AdditionalPhotographerRate { get; set; }
    [Range(typeof(decimal), "0.01", "999.99", ErrorMessage = "Duration must be greater than zero.")]
    public decimal DurationHours { get; set; }
    [Range(1, 100, ErrorMessage = "Number of photographers must be greater than zero.")]
    public int NumberOfPhotographers { get; set; }
    [Range(0, 1000000, ErrorMessage = "Edited photo count cannot be negative.")]
    public int EditedPhotoCount { get; set; }
    public bool AlbumIncluded { get; set; }
    public bool VideoIncluded { get; set; }
    public string Status { get; set; } = "Active";
    [MinLength(1, ErrorMessage = "Select at least one existing studio service.")]
    public List<Guid> ServiceIds { get; set; } = [];
    public IFormFile? CoverImage { get; set; }
}
