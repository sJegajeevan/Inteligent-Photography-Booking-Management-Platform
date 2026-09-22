namespace PhotographyBooking.Api.Models;

public enum PhotographyPackageStatus { Active, Inactive }

public class PhotographyPackage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StudioId { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal BasePrice { get; set; }
    public decimal ExtraHourRate { get; set; }
    public decimal AdditionalPhotographerRate { get; set; }
    public decimal DurationHours { get; set; }
    public int EditedPhotoCount { get; set; }
    public bool AlbumIncluded { get; set; }
    public bool VideoIncluded { get; set; }
    public string PackageName { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public string Duration { get; set; } = string.Empty;
    public int NumberOfPhotographers { get; set; }
    public string CoverImageUrl { get; set; } = string.Empty;
    public PhotographyPackageStatus Status { get; set; } = PhotographyPackageStatus.Active;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public Studio Studio { get; set; } = null!;
    public ICollection<PhotographyPackageService> PackageServices { get; set; } = new List<PhotographyPackageService>();
    public ICollection<PackageAddon> Addons { get; set; } = new List<PackageAddon>();
}
