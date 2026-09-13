using Microsoft.AspNetCore.Mvc;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/public/studios/{studioId:guid}/packages")]
public class PublicPackagesController(PhotographyPackageService packages) : ControllerBase
{
    [HttpGet] public async Task<ActionResult<IReadOnlyList<PhotographyPackageResponseDto>>> GetAll(Guid studioId) => Ok(await packages.GetPublicAsync(studioId));
    [HttpGet("{id:guid}")] public async Task<ActionResult<PhotographyPackageResponseDto>> Get(Guid studioId, Guid id) { var package = await packages.GetPublicAsync(studioId, id); return package is null ? NotFound(new { message = "Package was not found." }) : Ok(package); }
}
