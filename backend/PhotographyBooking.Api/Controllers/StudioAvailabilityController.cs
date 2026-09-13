using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.StudioAvailability;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/availability")]
[Authorize(Roles = "Studio")]
public class StudioAvailabilityController : ControllerBase
{
    private readonly StudioAvailabilityService _service;
    public StudioAvailabilityController(StudioAvailabilityService service) => _service = service;

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<StudioAvailabilityResponseDto>>> GetAll()
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return Ok(await _service.GetAllAsync(userId));
    }

    [HttpPost]
    public async Task<ActionResult<StudioAvailabilityResponseDto>> Create([FromBody] StudioAvailabilityRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await _service.CreateAsync(userId, request);
        return result.Status switch
        {
            AvailabilityWriteStatus.Success => CreatedAtAction(nameof(GetAll), result.Value),
            AvailabilityWriteStatus.StudioNotFound => NotFound(new { message = "Create a Studio profile before adding availability." }),
            _ => BadRequest(new { message = "Availability is already configured for this date." })
        };
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<StudioAvailabilityResponseDto>> Update(Guid id, [FromBody] StudioAvailabilityRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var result = await _service.UpdateAsync(userId, id, request);
        return result.Status switch
        {
            AvailabilityWriteStatus.Success => Ok(result.Value),
            AvailabilityWriteStatus.DuplicateDate => BadRequest(new { message = "Availability is already configured for this date." }),
            _ => NotFound(new { message = "Availability record was not found." })
        };
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return await _service.DeleteAsync(userId, id) ? NoContent() : NotFound(new { message = "Availability record was not found." });
    }

    private bool TryGetUserId(out int userId) => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
