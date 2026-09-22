using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.StudioPortfolio;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public class StudioPortfolioService
{
    private static readonly Dictionary<string, string> ExtensionByContentType = new(StringComparer.OrdinalIgnoreCase)
    {
        ["image/jpeg"] = ".jpg", ["image/png"] = ".png", ["image/webp"] = ".webp"
    };
    private readonly ApplicationDbContext _dbContext;
    private readonly string _uploadDirectory;

    public StudioPortfolioService(ApplicationDbContext dbContext, IWebHostEnvironment environment)
    {
        _dbContext = dbContext;
        var webRoot = environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot");
        _uploadDirectory = Path.Combine(webRoot, "uploads", "portfolio");
    }

    public async Task<IReadOnlyList<StudioPortfolioResponseDto>> GetAllAsync(int userId)
    {
        var items = await _dbContext.StudioPortfolios.AsNoTracking().Include(item => item.Images)
            .Where(item => item.Studio.UserId == userId).OrderByDescending(item => item.CreatedAt).ToListAsync();
        return items.Select(ToResponse).ToList();
    }

    public async Task<StudioPortfolioResponseDto?> CreateAsync(int userId, StudioPortfolioRequestDto request)
    {
        var studioId = await _dbContext.Studios.Where(s => s.UserId == userId).Select(s => (Guid?)s.Id).SingleOrDefaultAsync();
        if (studioId is null) return null;
        if (request.Photos.Count == 0) throw new ArgumentException("Select at least one photo.");

        var savedPaths = new List<string>();
        try
        {
            var now = DateTime.UtcNow;
            var item = new StudioPortfolio { StudioId = studioId.Value, Title = request.Title.Trim(), Description = request.Description?.Trim() ?? string.Empty, Category = request.Category.Trim(), CreatedAt = now, UpdatedAt = now };
            foreach (var photo in request.Photos)
            {
                var imageUrl = await SavePhotoAsync(photo);
                savedPaths.Add(imageUrl);
                item.Images.Add(new StudioPortfolioImage { ImageUrl = imageUrl, DisplayOrder = item.Images.Count, CreatedAt = now });
            }
            item.ImageUrl = item.Images.First().ImageUrl;
            _dbContext.StudioPortfolios.Add(item);
            await _dbContext.SaveChangesAsync();
            return ToResponse(item);
        }
        catch { DeleteFiles(savedPaths); throw; }
    }

    public async Task<StudioPortfolioResponseDto?> UpdateAsync(int userId, Guid id, StudioPortfolioRequestDto request)
    {
        var item = await _dbContext.StudioPortfolios.Include(p => p.Images).SingleOrDefaultAsync(p => p.Id == id && p.Studio.UserId == userId);
        if (item is null) return null;
        var removeIds = request.RemovedImageIds.ToHashSet();
        var removed = item.Images.Where(image => removeIds.Contains(image.Id)).ToList();
        if (item.Images.Count - removed.Count + request.Photos.Count == 0) throw new ArgumentException("A portfolio project must contain at least one photo.");

        var savedPaths = new List<string>();
        try
        {
            foreach (var image in removed) { item.Images.Remove(image); _dbContext.StudioPortfolioImages.Remove(image); }
            var nextOrder = item.Images.Count == 0 ? 0 : item.Images.Max(image => image.DisplayOrder) + 1;
            foreach (var photo in request.Photos)
            {
                var imageUrl = await SavePhotoAsync(photo);
                savedPaths.Add(imageUrl);
                var image = new StudioPortfolioImage
                {
                    StudioPortfolioId = item.Id,
                    ImageUrl = imageUrl,
                    DisplayOrder = nextOrder++,
                    CreatedAt = DateTime.UtcNow
                };
                item.Images.Add(image);
                _dbContext.StudioPortfolioImages.Add(image);
            }
            item.Title = request.Title.Trim(); item.Description = request.Description?.Trim() ?? string.Empty; item.Category = request.Category.Trim(); item.UpdatedAt = DateTime.UtcNow;
            item.ImageUrl = item.Images.OrderBy(image => image.DisplayOrder).First().ImageUrl;
            await _dbContext.SaveChangesAsync();
            DeleteFiles(removed.Select(image => image.ImageUrl));
            return ToResponse(item);
        }
        catch { DeleteFiles(savedPaths); throw; }
    }

    public async Task<bool> DeleteAsync(int userId, Guid id)
    {
        var item = await _dbContext.StudioPortfolios.Include(p => p.Images).SingleOrDefaultAsync(p => p.Id == id && p.Studio.UserId == userId);
        if (item is null) return false;
        var paths = item.Images.Select(image => image.ImageUrl).Append(item.ImageUrl).Distinct().ToList();
        _dbContext.StudioPortfolios.Remove(item);
        await _dbContext.SaveChangesAsync();
        DeleteFiles(paths);
        return true;
    }

    private async Task<string> SavePhotoAsync(IFormFile photo)
    {
        if (!ExtensionByContentType.TryGetValue(photo.ContentType, out var extension)) throw new ArgumentException("Only JPG, PNG and WEBP images are allowed.");
        if (!await HasValidImageSignatureAsync(photo, extension)) throw new ArgumentException("The selected file content is not a valid JPG, PNG or WEBP image.");
        Directory.CreateDirectory(_uploadDirectory);
        var fileName = $"{Guid.NewGuid():N}{extension}";
        var fullPath = Path.Combine(_uploadDirectory, fileName);
        await using var stream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await photo.CopyToAsync(stream);
        return $"/uploads/portfolio/{fileName}";
    }

    private static async Task<bool> HasValidImageSignatureAsync(IFormFile photo, string extension)
    {
        var header = new byte[12];
        await using var stream = photo.OpenReadStream();
        var bytesRead = await stream.ReadAsync(header);
        if (bytesRead < 12) return false;
        if (extension == ".jpg") return header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;
        if (extension == ".png") return header.AsSpan(0, 8).SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });
        return header.AsSpan(0, 4).SequenceEqual("RIFF"u8) && header.AsSpan(8, 4).SequenceEqual("WEBP"u8);
    }

    private void DeleteFiles(IEnumerable<string> imageUrls)
    {
        var root = Path.GetFullPath(_uploadDirectory) + Path.DirectorySeparatorChar;
        foreach (var imageUrl in imageUrls.Where(url => url.StartsWith("/uploads/portfolio/", StringComparison.OrdinalIgnoreCase)))
        {
            var fullPath = Path.GetFullPath(Path.Combine(_uploadDirectory, Path.GetFileName(imageUrl)));
            if (fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(fullPath)) File.Delete(fullPath);
        }
    }

    private static StudioPortfolioResponseDto ToResponse(StudioPortfolio item)
    {
        var images = item.Images.OrderBy(image => image.DisplayOrder).Select(image => new StudioPortfolioImageResponseDto { Id = image.Id, ImageUrl = image.ImageUrl, DisplayOrder = image.DisplayOrder }).ToList();
        return new StudioPortfolioResponseDto { Id = item.Id, StudioId = item.StudioId, Title = item.Title, Description = item.Description, ImageUrl = images.FirstOrDefault()?.ImageUrl ?? item.ImageUrl, Category = item.Category, CreatedAt = item.CreatedAt, UpdatedAt = item.UpdatedAt, Images = images };
    }
}
