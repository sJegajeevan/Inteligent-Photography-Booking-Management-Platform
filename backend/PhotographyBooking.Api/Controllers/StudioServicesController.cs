using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.StudioServices;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/services")]
[Authorize(Roles = "Studio")]
public class StudioServicesController : ControllerBase
{
    private readonly StudioServicesCrudService _service;

    public StudioServicesController(StudioServicesCrudService service) => _service = service;

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<StudioServiceResponseDto>>> GetAll()
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return Ok(await _service.GetAllAsync(userId));
    }

    [HttpPost]
    public async Task<ActionResult<StudioServiceResponseDto>> Create([FromBody] StudioServiceRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var service = await _service.CreateAsync(userId, request);
        return service is null
            ? NotFound(new { message = "Create a Studio profile before adding services." })
            : CreatedAtAction(nameof(GetAll), service);
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<StudioServiceResponseDto>> Update(Guid id, [FromBody] StudioServiceRequestDto request)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        var service = await _service.UpdateAsync(userId, id, request);
        return service is null ? NotFound(new { message = "Service was not found." }) : Ok(service);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized(new { message = "A valid user token is required." });
        return await _service.DeleteAsync(userId, id)
            ? NoContent()
            : NotFound(new { message = "Service was not found." });
    }

    private bool TryGetUserId(out int userId) =>
        int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
