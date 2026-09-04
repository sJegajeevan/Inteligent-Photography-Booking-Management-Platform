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

    [HttpPut]
    public async Task<ActionResult<StudioResponseDto>> SaveProfile([FromBody] UpdateStudioDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await _studioService.UpsertProfileAsync(userId, request);
        return result.Created ? CreatedAtAction(nameof(GetProfile), result.Profile) : Ok(result.Profile);
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
}
