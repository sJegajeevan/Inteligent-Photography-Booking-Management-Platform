using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/packages")]
[Authorize(Roles = "Studio")]
public class StudioPackagesController(PhotographyPackageService packages, PackagePriceCalculationService priceCalculator) : ControllerBase
{
    private const long MaxImageBytes = 5 * 1024 * 1024;
    [HttpGet] public async Task<ActionResult<IReadOnlyList<PhotographyPackageResponseDto>>> GetAll() => TryGetUserId(out var userId) ? Ok(await packages.GetMineAsync(userId)) : Unauthorized(new { message = "A valid user token is required." });
    [HttpGet("{id:guid}")] public async Task<ActionResult<PhotographyPackageResponseDto>> Get(Guid id) { if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." }); var package = await packages.GetMineAsync(userId, id); return package is null ? NotFound(new { message = "Package was not found." }) : Ok(package); }
    [HttpPost, Consumes("multipart/form-data"), RequestSizeLimit(5_500_000)] public Task<ActionResult<PhotographyPackageResponseDto>> Create([FromForm] PhotographyPackageRequestDto request) => Save(null, request);
    [HttpPut("{id:guid}"), Consumes("multipart/form-data"), RequestSizeLimit(5_500_000)] public Task<ActionResult<PhotographyPackageResponseDto>> Update(Guid id, [FromForm] PhotographyPackageRequestDto request) => Save(id, request);
    [HttpDelete("{id:guid}")] public async Task<IActionResult> Delete(Guid id) { if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." }); return await packages.DeleteAsync(userId, id) ? NoContent() : NotFound(new { message = "Package was not found." }); }
    [HttpPost("{id:guid}/calculate-price")]
    public async Task<ActionResult<PackagePriceCalculationResponseDto>> CalculatePrice(Guid id, [FromBody] PackagePriceCalculationRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await priceCalculator.CalculateAsync(userId, id, request);
        if (result.Result is null) return result.Error == "Package was not found." ? NotFound(new { message = result.Error }) : BadRequest(new { message = result.Error });
        return Ok(result.Result);
    }
    private async Task<ActionResult<PhotographyPackageResponseDto>> Save(Guid? id, PhotographyPackageRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var fileError = ValidateImage(request.CoverImage); if (fileError is not null) return BadRequest(new { message = fileError });
        try { var result = id is null ? await packages.CreateAsync(userId, request) : await packages.UpdateAsync(userId, id.Value, request); if (result.Error is not null) return BadRequest(new { message = result.Error }); if (result.Package is null) return NotFound(new { message = id is null ? "Create a Studio profile before adding packages." : "Package was not found." }); return id is null ? CreatedAtAction(nameof(Get), new { id = result.Package.Id }, result.Package) : Ok(result.Package); }
        catch (ArgumentException error) { return BadRequest(new { message = error.Message }); }
    }
    private static string? ValidateImage(IFormFile? image)
    {
        if (image is null) return null;
        var extension = Path.GetExtension(image.FileName); var valid = (image.ContentType.Equals("image/jpeg", StringComparison.OrdinalIgnoreCase) && (extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) || extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase))) || (image.ContentType.Equals("image/png", StringComparison.OrdinalIgnoreCase) && extension.Equals(".png", StringComparison.OrdinalIgnoreCase)) || (image.ContentType.Equals("image/webp", StringComparison.OrdinalIgnoreCase) && extension.Equals(".webp", StringComparison.OrdinalIgnoreCase));
        if (!valid) return "Only JPG, PNG and WEBP images are allowed."; if (image.Length <= 0) return "Empty image files are not allowed."; return image.Length > MaxImageBytes ? "Cover image must be smaller than 5 MB." : null;
    }
    private bool TryGetUserId(out int userId) => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
