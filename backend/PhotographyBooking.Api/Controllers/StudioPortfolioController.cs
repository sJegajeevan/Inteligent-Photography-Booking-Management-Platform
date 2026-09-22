using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.StudioPortfolio;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/portfolio")]
[Authorize(Roles = "Studio")]
public class StudioPortfolioController : ControllerBase
{
    private const long MaxImageBytes = 5 * 1024 * 1024;
    private const int MaxImagesPerRequest = 20;
    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase) { "image/jpeg", "image/png", "image/webp" };
    private static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase) { ".jpg", ".jpeg", ".png", ".webp" };
    private readonly StudioPortfolioService _portfolioService;

    public StudioPortfolioController(StudioPortfolioService portfolioService) => _portfolioService = portfolioService;

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<StudioPortfolioResponseDto>>> GetAll()
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return Ok(await _portfolioService.GetAllAsync(userId));
    }

    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(105_000_000)]
    public async Task<ActionResult<StudioPortfolioResponseDto>> Create([FromForm] StudioPortfolioRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var fileError = ValidatePhotos(request.Photos, requireOne: true);
        if (fileError is not null) return BadRequest(new { message = fileError });
        StudioPortfolioResponseDto? item;
        try { item = await _portfolioService.CreateAsync(userId, request); }
        catch (ArgumentException error) { return BadRequest(new { message = error.Message }); }
        return item is null
            ? NotFound(new { message = "Create a Studio profile before adding portfolio items." })
            : CreatedAtAction(nameof(GetAll), item);
    }

    [HttpPut("{id:guid}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(105_000_000)]
    public async Task<ActionResult<StudioPortfolioResponseDto>> Update(Guid id, [FromForm] StudioPortfolioRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var fileError = ValidatePhotos(request.Photos, requireOne: false);
        if (fileError is not null) return BadRequest(new { message = fileError });
        StudioPortfolioResponseDto? item;
        try { item = await _portfolioService.UpdateAsync(userId, id, request); }
        catch (ArgumentException error) { return BadRequest(new { message = error.Message }); }
        return item is null ? NotFound(new { message = "Portfolio item was not found." }) : Ok(item);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return await _portfolioService.DeleteAsync(userId, id)
            ? NoContent()
            : NotFound(new { message = "Portfolio item was not found." });
    }

    private bool TryGetUserId(out int userId) => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);

    private static string? ValidatePhotos(IReadOnlyCollection<IFormFile> photos, bool requireOne)
    {
        if (requireOne && photos.Count == 0) return "Select at least one photo.";
        if (photos.Count > MaxImagesPerRequest) return $"Select no more than {MaxImagesPerRequest} photos at a time.";
        foreach (var photo in photos)
        {
            var extension = Path.GetExtension(photo.FileName);
            var typeMatchesExtension = photo.ContentType.Equals("image/jpeg", StringComparison.OrdinalIgnoreCase) && (extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) || extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase))
                || photo.ContentType.Equals("image/png", StringComparison.OrdinalIgnoreCase) && extension.Equals(".png", StringComparison.OrdinalIgnoreCase)
                || photo.ContentType.Equals("image/webp", StringComparison.OrdinalIgnoreCase) && extension.Equals(".webp", StringComparison.OrdinalIgnoreCase);
            if (!AllowedContentTypes.Contains(photo.ContentType) || !AllowedExtensions.Contains(extension) || !typeMatchesExtension)
                return "Only JPG, PNG and WEBP images are allowed.";
            if (photo.Length <= 0) return "Empty image files are not allowed.";
            if (photo.Length > MaxImageBytes) return "Each image must be smaller than 5 MB.";
        }
        return null;
    }
}
