using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/public/studios/{studioId:guid}/packages")]
public class PublicPackagesController(PhotographyPackageService packages, PackagePriceCalculationService priceCalculator) : ControllerBase
{
    [HttpGet] public async Task<ActionResult<IReadOnlyList<PhotographyPackageResponseDto>>> GetAll(Guid studioId) => Ok(await packages.GetPublicAsync(studioId));
    [HttpGet("{id:guid}")] public async Task<ActionResult<PhotographyPackageResponseDto>> Get(Guid studioId, Guid id) { var package = await packages.GetPublicAsync(studioId, id); return package is null ? NotFound(new { message = "Package was not found." }) : Ok(package); }

    [HttpPost("{id:guid}/calculate-price")]
    public async Task<ActionResult<PackagePriceCalculationResponseDto>> CalculatePrice(Guid studioId, Guid id, [FromBody] PackagePriceCalculationRequestDto request)
    {
        var result = await priceCalculator.CalculatePublicAsync(studioId, id, request);
        if (result.Result is null) return result.Error == "Package was not found." ? NotFound(new { message = result.Error }) : BadRequest(new { message = result.Error });
        return Ok(result.Result);
    }

    // Read-only search. Candidates are point-in-time evidence, never a reservation.
    [AllowAnonymous]
    [HttpPost("{packageId:guid}/available-slots")]
    public async Task<ActionResult<SchedulingCandidateResponseDto>> AvailableSlots(Guid studioId, Guid packageId,
        [FromBody] SchedulingCandidateRequestDto request, [FromServices] SchedulingCandidateService scheduling,
        CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid) return ValidationProblem(statusCode: StatusCodes.Status400BadRequest, modelStateDictionary: ModelState);
        try
        {
            var result = await scheduling.DiscoverAsync(studioId, packageId, request, cancellationToken);
            return result.ErrorCode switch
            {
                "invalid_scheduling_input" => BadRequest(new { message = "Invalid scheduling request.", code = "invalid_scheduling_input" }),
                "package_unavailable" => NotFound(new { message = "Package was not found or is unavailable.", code = "package_unavailable" }),
                null when result.Response is not null => Ok(result.Response),
                _ => SchedulingFailure()
            };
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception)
        {
            // No exception text, entities, or conflict details reach public responses, even in Development.
            return SchedulingFailure();
        }
    }

    private ObjectResult SchedulingFailure() => Problem(statusCode: StatusCodes.Status500InternalServerError,
        title: "Unable to retrieve scheduling candidates.");
}
