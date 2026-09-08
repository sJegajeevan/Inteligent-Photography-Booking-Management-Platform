using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PackageAddons;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Models;
using PackageServiceLink = PhotographyBooking.Api.Models.PhotographyPackageService;

namespace PhotographyBooking.Api.Services;

public class PhotographyPackageService
{
    private readonly ApplicationDbContext _db;
    private readonly string _uploadDirectory;
    public PhotographyPackageService(ApplicationDbContext db, IWebHostEnvironment environment)
    {
        _db = db;
        var root = environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot");
        _uploadDirectory = Path.Combine(root, "uploads", "packages");
    }

    public async Task<IReadOnlyList<PhotographyPackageResponseDto>> GetMineAsync(int userId) =>
        (await OwnedQuery(userId).AsNoTracking().OrderByDescending(p => p.CreatedAt).ToListAsync()).Select(ToResponse).ToList();

    public async Task<PhotographyPackageResponseDto?> GetMineAsync(int userId, Guid id)
    {
        var package = await OwnedQuery(userId).AsNoTracking().SingleOrDefaultAsync(p => p.Id == id);
        return package is null ? null : ToResponse(package);
    }

    public async Task<(PhotographyPackageResponseDto? Package, string? Error)> CreateAsync(int userId, PhotographyPackageRequestDto request)
    {
        var studio = await _db.Studios.SingleOrDefaultAsync(s => s.UserId == userId);
        if (studio is null) return (null, "Create a Studio profile before adding packages.");
        if (!TryGetStatus(request.Status, out var status)) return (null, "Status must be Active or Inactive.");
        var services = await GetOwnedServicesAsync(studio.Id, request.ServiceIds);
        if (services is null) return (null, "Every selected service must belong to your studio.");
        var savedImage = string.Empty;
        try
        {
            if (request.CoverImage is not null) savedImage = await SaveImageAsync(request.CoverImage);
            var now = DateTime.UtcNow;
            var package = new PhotographyPackage { StudioId = studio.Id, Name = request.Name.Trim(), Description = request.Description?.Trim() ?? string.Empty, BasePrice = request.BasePrice, ExtraHourRate = request.ExtraHourRate, AdditionalPhotographerRate = request.AdditionalPhotographerRate, DurationHours = request.DurationHours, NumberOfPhotographers = request.NumberOfPhotographers, EditedPhotoCount = request.EditedPhotoCount, AlbumIncluded = request.AlbumIncluded, VideoIncluded = request.VideoIncluded, PackageName = request.Name.Trim(), Price = request.BasePrice, Duration = $"{request.DurationHours:0.##} hours", Status = status, CoverImageUrl = savedImage, CreatedAt = now, UpdatedAt = now };
            foreach (var service in services) package.PackageServices.Add(new PackageServiceLink { StudioServiceId = service.Id, StudioService = service });
            _db.PhotographyPackages.Add(package);
            await _db.SaveChangesAsync();
            return (ToResponse(package), null);
        }
        catch { DeleteImage(savedImage); throw; }
    }

    public async Task<(PhotographyPackageResponseDto? Package, string? Error)> UpdateAsync(int userId, Guid id, PhotographyPackageRequestDto request)
    {
        var package = await OwnedQuery(userId).SingleOrDefaultAsync(p => p.Id == id);
        if (package is null) return (null, null);
        if (!TryGetStatus(request.Status, out var status)) return (null, "Status must be Active or Inactive.");
        var services = await GetOwnedServicesAsync(package.StudioId, request.ServiceIds);
        if (services is null) return (null, "Every selected service must belong to your studio.");
        var savedImage = string.Empty;
        try
        {
            if (request.CoverImage is not null) savedImage = await SaveImageAsync(request.CoverImage);
            var previousImage = package.CoverImageUrl;
            package.Name = request.Name.Trim(); package.Description = request.Description?.Trim() ?? string.Empty; package.BasePrice = request.BasePrice; package.ExtraHourRate = request.ExtraHourRate; package.AdditionalPhotographerRate = request.AdditionalPhotographerRate; package.DurationHours = request.DurationHours; package.NumberOfPhotographers = request.NumberOfPhotographers; package.EditedPhotoCount = request.EditedPhotoCount; package.AlbumIncluded = request.AlbumIncluded; package.VideoIncluded = request.VideoIncluded; package.PackageName = request.Name.Trim(); package.Price = request.BasePrice; package.Duration = $"{request.DurationHours:0.##} hours"; package.Status = status; package.UpdatedAt = DateTime.UtcNow;
            if (!string.IsNullOrEmpty(savedImage)) package.CoverImageUrl = savedImage;
            _db.PhotographyPackageServices.RemoveRange(package.PackageServices);
            package.PackageServices.Clear();
            foreach (var service in services) package.PackageServices.Add(new PackageServiceLink { PhotographyPackageId = package.Id, StudioServiceId = service.Id, StudioService = service });
            await _db.SaveChangesAsync();
            if (!string.IsNullOrEmpty(savedImage)) DeleteImage(previousImage);
            return (ToResponse(package), null);
        }
        catch { DeleteImage(savedImage); throw; }
    }

    public async Task<bool> DeleteAsync(int userId, Guid id)
    {
        var package = await OwnedQuery(userId).SingleOrDefaultAsync(p => p.Id == id);
        if (package is null) return false;
        var image = package.CoverImageUrl;
        _db.PhotographyPackages.Remove(package);
        await _db.SaveChangesAsync();
        DeleteImage(image);
        return true;
    }

    public async Task<IReadOnlyList<PhotographyPackageResponseDto>> GetPublicAsync(Guid studioId) =>
        (await _db.PhotographyPackages.AsNoTracking().Include(p => p.PackageServices).ThenInclude(link => link.StudioService).Include(p => p.Addons).Where(p => p.StudioId == studioId && p.Status == PhotographyPackageStatus.Active).OrderBy(p => p.PackageName).ToListAsync()).Select(ToResponse).ToList();
    public async Task<PhotographyPackageResponseDto?> GetPublicAsync(Guid studioId, Guid id)
    {
        var package = await _db.PhotographyPackages.AsNoTracking().Include(p => p.PackageServices).ThenInclude(link => link.StudioService).Include(p => p.Addons).SingleOrDefaultAsync(p => p.StudioId == studioId && p.Id == id && p.Status == PhotographyPackageStatus.Active);
        return package is null ? null : ToResponse(package);
    }

    private IQueryable<PhotographyPackage> OwnedQuery(int userId) => _db.PhotographyPackages.Include(p => p.PackageServices).ThenInclude(link => link.StudioService).Include(p => p.Addons).Where(p => p.Studio.UserId == userId);
    private async Task<List<StudioService>?> GetOwnedServicesAsync(Guid studioId, IEnumerable<Guid> serviceIds)
    {
        var ids = serviceIds.Distinct().ToList();
        if (ids.Count == 0) return null;
        var services = await _db.StudioServices.Where(service => service.StudioId == studioId && ids.Contains(service.Id)).ToListAsync();
        return services.Count == ids.Count ? services : null;
    }
    private async Task<string> SaveImageAsync(IFormFile image)
    {
        var extension = image.ContentType.ToLowerInvariant() switch { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp", _ => throw new ArgumentException("Only JPG, PNG and WEBP images are allowed.") };
        if (!await HasValidImageSignatureAsync(image, extension)) throw new ArgumentException("The selected file content is not a valid JPG, PNG or WEBP image.");
        Directory.CreateDirectory(_uploadDirectory);
        var name = $"{Guid.NewGuid():N}{extension}";
        await using var stream = new FileStream(Path.Combine(_uploadDirectory, name), FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await image.CopyToAsync(stream);
        return $"/uploads/packages/{name}";
    }
    private static async Task<bool> HasValidImageSignatureAsync(IFormFile image, string extension)
    {
        var header = new byte[12]; await using var stream = image.OpenReadStream(); var read = await stream.ReadAsync(header); if (read < 12) return false;
        return extension switch { ".jpg" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF, ".png" => header.AsSpan(0, 8).SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }), _ => header.AsSpan(0, 4).SequenceEqual("RIFF"u8) && header.AsSpan(8, 4).SequenceEqual("WEBP"u8) };
    }
    private void DeleteImage(string? url) { if (string.IsNullOrWhiteSpace(url) || !url.StartsWith("/uploads/packages/", StringComparison.OrdinalIgnoreCase)) return; var path = Path.Combine(_uploadDirectory, Path.GetFileName(url)); if (File.Exists(path)) File.Delete(path); }
    private static bool TryGetStatus(string? raw, out PhotographyPackageStatus status) => Enum.TryParse(raw, true, out status) && Enum.IsDefined(status);
    private static PhotographyPackageResponseDto ToResponse(PhotographyPackage p) => new() { Id = p.Id, StudioId = p.StudioId, Name = string.IsNullOrWhiteSpace(p.Name) ? p.PackageName : p.Name, Description = p.Description, BasePrice = p.BasePrice == 0 ? p.Price : p.BasePrice, ExtraHourRate = p.ExtraHourRate, AdditionalPhotographerRate = p.AdditionalPhotographerRate, DurationHours = p.DurationHours, NumberOfPhotographers = p.NumberOfPhotographers, EditedPhotoCount = p.EditedPhotoCount, AlbumIncluded = p.AlbumIncluded, VideoIncluded = p.VideoIncluded, CoverImageUrl = p.CoverImageUrl, Status = p.Status.ToString(), CreatedAt = p.CreatedAt, UpdatedAt = p.UpdatedAt, Services = p.PackageServices.OrderBy(link => link.StudioService.ServiceName).Select(link => new PhotographyPackageServiceDto { Id = link.StudioServiceId, ServiceName = link.StudioService.ServiceName, Description = link.StudioService.Description }).ToList(), Addons = p.Addons.OrderBy(addon => addon.Name).Select(addon => new PackageAddonResponseDto { Id = addon.Id, PackageId = addon.PackageId, Name = addon.Name, Description = addon.Description, Price = addon.Price, CreatedAt = addon.CreatedAt, UpdatedAt = addon.UpdatedAt }).ToList() };
}
