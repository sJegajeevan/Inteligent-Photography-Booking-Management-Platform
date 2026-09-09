using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.PackageAddons;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/packages/{packageId:guid}/addons")]
[Authorize(Roles = "Studio")]
public class PackageAddonsController(PackageAddonService addons) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PackageAddonResponseDto>>> GetAll(Guid packageId)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await addons.GetMineAsync(userId, packageId);
        return result is null ? NotFound(new { message = "Package was not found." }) : Ok(result);
    }

    [HttpPost]
    public async Task<ActionResult<PackageAddonResponseDto>> Create(Guid packageId, PackageAddonRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await addons.CreateAsync(userId, packageId, request);
        if (result.Error is not null) return NotFound(new { message = result.Error });
        return CreatedAtAction(nameof(GetAll), new { packageId }, result.Addon);
    }

    [HttpPut("{addonId:guid}")]
    public async Task<ActionResult<PackageAddonResponseDto>> Update(Guid packageId, Guid addonId, PackageAddonRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await addons.UpdateAsync(userId, packageId, addonId, request);
        return result.Addon is null ? NotFound(new { message = result.Error }) : Ok(result.Addon);
    }

    [HttpDelete("{addonId:guid}")]
    public async Task<IActionResult> Delete(Guid packageId, Guid addonId)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return await addons.DeleteAsync(userId, packageId, addonId) ? NoContent() : NotFound(new { message = "Add-on was not found." });
    }

    private bool TryGetUserId(out int userId) => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
