using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.PackageAddons;

public class PackageAddonRequestDto
{
    [Required, StringLength(160), RegularExpression(@".*\S.*", ErrorMessage = "Add-on name is required.")]
    public string Name { get; set; } = string.Empty;
    [StringLength(1000)]
    public string? Description { get; set; }
    [Range(typeof(decimal), "0", "9999999999.99", ErrorMessage = "Price must be zero or greater.")]
    public decimal Price { get; set; }
}