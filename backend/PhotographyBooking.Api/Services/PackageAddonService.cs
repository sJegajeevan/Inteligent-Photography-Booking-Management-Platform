using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PackageAddons;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public class PackageAddonService
{
    private readonly ApplicationDbContext _db;
    public PackageAddonService(ApplicationDbContext db) => _db = db;

    public async Task<IReadOnlyList<PackageAddonResponseDto>?> GetMineAsync(int userId, Guid packageId)
    {
        if (!await OwnsPackageAsync(userId, packageId)) return null;
        return await _db.PackageAddons.AsNoTracking().Where(addon => addon.PackageId == packageId).OrderBy(addon => addon.Name).Select(ToResponse).ToListAsync();
    }

    public async Task<(PackageAddonResponseDto? Addon, string? Error)> CreateAsync(int userId, Guid packageId, PackageAddonRequestDto request)
    {
        if (!await OwnsPackageAsync(userId, packageId)) return (null, "Package was not found.");
        var now = DateTime.UtcNow;
        var addon = new PackageAddon { PackageId = packageId, Name = request.Name.Trim(), Description = request.Description?.Trim() ?? string.Empty, Price = request.Price, CreatedAt = now, UpdatedAt = now };
        _db.PackageAddons.Add(addon);
        await _db.SaveChangesAsync();
        return (ToResponse(addon), null);
    }

    public async Task<(PackageAddonResponseDto? Addon, string? Error)> UpdateAsync(int userId, Guid packageId, Guid addonId, PackageAddonRequestDto request)
    {
        var addon = await _db.PackageAddons.SingleOrDefaultAsync(item => item.Id == addonId && item.PackageId == packageId && item.Package.Studio.UserId == userId);
        if (addon is null) return (null, "Add-on was not found.");
        addon.Name = request.Name.Trim();
        addon.Description = request.Description?.Trim() ?? string.Empty;
        addon.Price = request.Price;
        addon.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return (ToResponse(addon), null);
    }

    public async Task<bool> DeleteAsync(int userId, Guid packageId, Guid addonId)
    {
        var addon = await _db.PackageAddons.SingleOrDefaultAsync(item => item.Id == addonId && item.PackageId == packageId && item.Package.Studio.UserId == userId);
        if (addon is null) return false;
        _db.PackageAddons.Remove(addon);
        await _db.SaveChangesAsync();
        return true;
    }

    private Task<bool> OwnsPackageAsync(int userId, Guid packageId) => _db.PhotographyPackages.AnyAsync(package => package.Id == packageId && package.Studio.UserId == userId);
    private static PackageAddonResponseDto ToResponse(PackageAddon addon) => new() { Id = addon.Id, PackageId = addon.PackageId, Name = addon.Name, Description = addon.Description, Price = addon.Price, CreatedAt = addon.CreatedAt, UpdatedAt = addon.UpdatedAt };
}
