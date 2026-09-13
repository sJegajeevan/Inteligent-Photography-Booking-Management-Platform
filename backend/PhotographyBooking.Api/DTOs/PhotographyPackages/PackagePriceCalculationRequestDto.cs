using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.PhotographyPackages;

public class PackagePriceCalculationRequestDto
{
    public List<Guid> SelectedAddonIds { get; set; } = [];
    [Range(0, 1000, ErrorMessage = "Extra hours cannot be negative.")]
    public int ExtraHours { get; set; }
    [Range(0, 100, ErrorMessage = "Additional photographers cannot be negative.")]
    public int AdditionalPhotographers { get; set; }
}