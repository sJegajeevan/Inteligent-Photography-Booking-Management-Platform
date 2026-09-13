using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.Services;

public class PackagePriceCalculationService
{
    private readonly ApplicationDbContext _db;
    public PackagePriceCalculationService(ApplicationDbContext db) => _db = db;

    public async Task<(PackagePriceCalculationResponseDto? Result, string? Error)> CalculateAsync(int userId, Guid packageId, PackagePriceCalculationRequestDto request)
    {
        var package = await _db.PhotographyPackages.Include(item => item.Addons).SingleOrDefaultAsync(item => item.Id == packageId && item.Studio.UserId == userId);
        if (package is null) return (null, "Package was not found.");
        if (request.ExtraHours < 0 || request.AdditionalPhotographers < 0) return (null, "Extra hours and additional photographers cannot be negative.");
        var selectedIds = request.SelectedAddonIds.ToList();
        if (selectedIds.Count != selectedIds.Distinct().Count()) return (null, "An add-on can only be selected once.");
        var selected = package.Addons.Where(addon => selectedIds.Contains(addon.Id)).ToList();
        if (selected.Count != selectedIds.Count) return (null, "One or more selected add-ons do not belong to this package.");
        var basePrice = package.BasePrice == 0 ? package.Price : package.BasePrice;
        if (basePrice < 0 || package.ExtraHourRate < 0 || package.AdditionalPhotographerRate < 0 || selected.Any(addon => addon.Price < 0)) return (null, "Package pricing data is invalid.");
        var addonTotal = selected.Sum(addon => addon.Price);
        decimal extraHoursCost;
        decimal photographerCost;
        decimal finalPrice;
        try
        {
            extraHoursCost = checked(request.ExtraHours * package.ExtraHourRate);
            photographerCost = checked(request.AdditionalPhotographers * package.AdditionalPhotographerRate);
            finalPrice = checked(basePrice + addonTotal + extraHoursCost + photographerCost);
        }
        catch (OverflowException)
        {
            return (null, "The calculated package price is too large.");
        }
        return (new PackagePriceCalculationResponseDto { PackageId = package.Id, PackageName = string.IsNullOrWhiteSpace(package.Name) ? package.PackageName : package.Name, BasePrice = basePrice, SelectedAddons = selected.Select(addon => new SelectedPackageAddonDto { Id = addon.Id, Name = addon.Name, Price = addon.Price }).ToList(), ExtraHours = request.ExtraHours, ExtraHoursCost = extraHoursCost, AdditionalPhotographers = request.AdditionalPhotographers, AdditionalPhotographersCost = photographerCost, FinalPrice = finalPrice }, null);
    }
}