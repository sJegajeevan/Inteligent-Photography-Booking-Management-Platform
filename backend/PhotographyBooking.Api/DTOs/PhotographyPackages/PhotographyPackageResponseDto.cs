using PhotographyBooking.Api.DTOs.PackageAddons;

namespace PhotographyBooking.Api.DTOs.PhotographyPackages;

public class PhotographyPackageServiceDto
{
    public Guid Id { get; set; }
    public string ServiceName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
}

public class PhotographyPackageResponseDto
{
    public Guid Id { get; set; }
    public Guid StudioId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public decimal BasePrice { get; set; }
    public decimal ExtraHourRate { get; set; }
    public decimal AdditionalPhotographerRate { get; set; }
    public decimal DurationHours { get; set; }
    public int NumberOfPhotographers { get; set; }
    public int EditedPhotoCount { get; set; }
    public bool AlbumIncluded { get; set; }
    public bool VideoIncluded { get; set; }
    public string CoverImageUrl { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public IReadOnlyList<PhotographyPackageServiceDto> Services { get; set; } = [];
    public IReadOnlyList<PackageAddonResponseDto> Addons { get; set; } = [];
}
