namespace PhotographyBooking.Api.DTOs.PhotographyPackages;

public class SelectedPackageAddonDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
}

public class PackagePriceCalculationResponseDto
{
    public Guid PackageId { get; set; }
    public string PackageName { get; set; } = string.Empty;
    public decimal BasePrice { get; set; }
    public IReadOnlyList<SelectedPackageAddonDto> SelectedAddons { get; set; } = [];
    public int ExtraHours { get; set; }
    public decimal ExtraHoursCost { get; set; }
    public int AdditionalPhotographers { get; set; }
    public decimal AdditionalPhotographersCost { get; set; }
    public decimal FinalPrice { get; set; }
}