namespace PhotographyBooking.Api.DTOs.PackageAddons;

public class PackageAddonResponseDto
{
    public Guid Id { get; set; }
    public Guid PackageId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}