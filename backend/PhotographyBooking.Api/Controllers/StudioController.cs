using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.Studio;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/profile")]
[Authorize(Roles = "Studio")]
public class StudioController : ControllerBase
{
    private readonly StudioService _studioService;
    public StudioController(StudioService studioService) => _studioService = studioService;

    [HttpGet]
    public async Task<ActionResult<StudioResponseDto>> GetProfile()
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var profile = await _studioService.GetProfileAsync(userId);
        return profile is null
            ? NotFound(new { message = "Studio profile has not been created yet." })
            : Ok(profile);
    }

    [HttpPut, Consumes("multipart/form-data"), RequestSizeLimit(10_500_000)]
    public async Task<ActionResult<StudioResponseDto>> SaveProfile([FromForm] UpdateStudioDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var fileError = ValidateImage(request.LogoImage, "Profile picture") ?? ValidateImage(request.CoverImage, "Cover photo");
        if (fileError is not null) return BadRequest(new { message = fileError });
        try
        {
            var result = await _studioService.UpsertProfileAsync(userId, request);
            return result.Created ? CreatedAtAction(nameof(GetProfile), result.Profile) : Ok(result.Profile);
        }
        catch (ArgumentException error) { return BadRequest(new { message = error.Message }); }
    }

    [HttpDelete]
    public async Task<IActionResult> DeleteProfile()
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return await _studioService.DeleteProfileAsync(userId)
            ? NoContent()
            : NotFound(new { message = "Studio profile has not been created yet." });
    }

    private bool TryGetUserId(out int userId) => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);

    private static string? ValidateImage(IFormFile? image, string label)
    {
        if (image is null) return null;
        var extension = Path.GetExtension(image.FileName);
        var valid = (image.ContentType.Equals("image/jpeg", StringComparison.OrdinalIgnoreCase) && (extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) || extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase))) ||
            (image.ContentType.Equals("image/png", StringComparison.OrdinalIgnoreCase) && extension.Equals(".png", StringComparison.OrdinalIgnoreCase)) ||
            (image.ContentType.Equals("image/webp", StringComparison.OrdinalIgnoreCase) && extension.Equals(".webp", StringComparison.OrdinalIgnoreCase));
        if (!valid) return $"{label} must be a JPG, PNG or WEBP image.";
        if (image.Length <= 0) return $"{label} cannot be empty.";
        return image.Length > 5 * 1024 * 1024 ? $"{label} must be smaller than 5 MB." : null;
    }
}
