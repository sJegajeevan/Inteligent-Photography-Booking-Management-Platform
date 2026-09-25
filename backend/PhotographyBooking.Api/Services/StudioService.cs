using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Studio;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public class StudioService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly string _uploadDirectory;
    public StudioService(ApplicationDbContext dbContext, IWebHostEnvironment environment)
    {
        _dbContext = dbContext;
        var root = environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot");
        _uploadDirectory = Path.Combine(root, "uploads", "studio");
    }

    public async Task<StudioResponseDto?> GetProfileAsync(int userId)
    {
        var studio = await _dbContext.Studios.AsNoTracking().SingleOrDefaultAsync(s => s.UserId == userId);
        return studio is null ? null : ToResponse(studio);
    }

    public async Task<(StudioResponseDto Profile, bool Created)> UpsertProfileAsync(int userId, UpdateStudioDto request)
    {
        System.ComponentModel.DataAnnotations.Validator.ValidateObject(request,
            new System.ComponentModel.DataAnnotations.ValidationContext(request), validateAllProperties: true);
        var studio = await _dbContext.Studios.SingleOrDefaultAsync(s => s.UserId == userId);
        var created = studio is null;
        if (studio is null) { studio = new Studio { UserId = userId }; _dbContext.Studios.Add(studio); }
        studio.StudioName = request.StudioName.Trim(); studio.Description = request.Description.Trim();
        studio.Location = request.Location.Trim(); studio.Address = request.Address.Trim();
        studio.Latitude = request.Latitude;
        studio.Longitude = request.Longitude;
        studio.ContactNumber = request.ContactNumber.Trim();
        studio.Email = request.Email.Trim().ToLowerInvariant();
        studio.ExperienceYears = request.ExperienceYears;
        studio.PhotographyTypes = request.PhotographyTypes.Trim();
        studio.StartingPrice = request.StartingPrice;
        var newLogo = request.LogoImage is null ? null : await SaveImageAsync(request.LogoImage, "logo");
        var newCover = request.CoverImage is null ? null : await SaveImageAsync(request.CoverImage, "cover");
        var oldLogo = studio.LogoUrl; var oldCover = studio.CoverPhotoUrl;
        if (newLogo is not null) studio.LogoUrl = newLogo;
        if (newCover is not null) studio.CoverPhotoUrl = newCover;
        try
        {
            await _dbContext.SaveChangesAsync();
            if (newLogo is not null) DeleteImage(oldLogo);
            if (newCover is not null) DeleteImage(oldCover);
            return (ToResponse(studio), created);
        }
        catch
        {
            DeleteImage(newLogo); DeleteImage(newCover); throw;
        }
    }

    public async Task<bool> DeleteProfileAsync(int userId)
    {
        var studio = await _dbContext.Studios.SingleOrDefaultAsync(s => s.UserId == userId);
        if (studio is null) return false;
        var logo = studio.LogoUrl; var cover = studio.CoverPhotoUrl;
        _dbContext.Studios.Remove(studio);
        await _dbContext.SaveChangesAsync();
        DeleteImage(logo); DeleteImage(cover);
        return true;
    }

    private static StudioResponseDto ToResponse(Studio studio) => new()
    {
        Id = studio.Id, StudioName = studio.StudioName, Description = studio.Description,
        Latitude = studio.Latitude, Longitude = studio.Longitude,
        Location = studio.Location, Address = studio.Address, ContactNumber = studio.ContactNumber,
        Email = studio.Email, ExperienceYears = studio.ExperienceYears,
        PhotographyTypes = studio.PhotographyTypes, StartingPrice = studio.StartingPrice,
        LogoUrl = studio.LogoUrl, CoverPhotoUrl = studio.CoverPhotoUrl
    };

    private async Task<string> SaveImageAsync(IFormFile image, string prefix)
    {
        var extension = image.ContentType.ToLowerInvariant() switch { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp", _ => throw new ArgumentException("Only JPG, PNG and WEBP images are allowed.") };
        if (!await HasValidImageSignatureAsync(image, extension)) throw new ArgumentException("The selected image content is not valid.");
        Directory.CreateDirectory(_uploadDirectory);
        var name = $"{prefix}-{Guid.NewGuid():N}{extension}";
        await using var stream = new FileStream(Path.Combine(_uploadDirectory, name), FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await image.CopyToAsync(stream);
        return $"/uploads/studio/{name}";
    }

    private static async Task<bool> HasValidImageSignatureAsync(IFormFile image, string extension)
    {
        var header = new byte[12]; await using var stream = image.OpenReadStream(); var read = await stream.ReadAsync(header); if (read < 12) return false;
        return extension switch { ".jpg" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF, ".png" => header.AsSpan(0, 8).SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }), _ => header.AsSpan(0, 4).SequenceEqual("RIFF"u8) && header.AsSpan(8, 4).SequenceEqual("WEBP"u8) };
    }

    private void DeleteImage(string? url)
    {
        if (string.IsNullOrWhiteSpace(url) || !url.StartsWith("/uploads/studio/", StringComparison.OrdinalIgnoreCase)) return;
        var path = Path.Combine(_uploadDirectory, Path.GetFileName(url)); if (File.Exists(path)) File.Delete(path);
    }
}
