using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

/// <summary>Public, stateless, read-only selection validation; never approval or authenticated evidence.</summary>
[ApiController]
[AllowAnonymous]
[SanitizedRecommendationRequest]
// Guid model binding (rather than :guid route constraints) gives malformed UUIDs HTTP 400.
[Route("api/public/studios/{studioId}/packages/{packageId}/validate-recommendation")]
public sealed class RecommendationValidationController(FinalRecommendationValidationService validation) : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<FinalValidationResult>> ValidateRecommendation(
        [FromRoute] Guid studioId, [FromRoute] Guid packageId,
        [FromBody] FinalValidationRequest request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!ModelState.IsValid || studioId == Guid.Empty || packageId == Guid.Empty ||
            request?.Requirements is null || request.Selection?.Customization is null ||
            request.PriorEvidence?.Selection?.Customization is null)
            return BadRequest(new { message = "Invalid recommendation validation request." });

        // Route IDs cannot be replaced by the selected or prior-evidence body IDs.
        if (request.Selection.StudioId != studioId || request.Selection.PackageId != packageId ||
            request.PriorEvidence.Selection.StudioId != studioId || request.PriorEvidence.Selection.PackageId != packageId)
            return BadRequest(new { message = "Selection references must match the route." });

        try
        {
            var result = await validation.CheckAsync(request, cancellationToken);
            // Step 1 owns structural constraints too; do not duplicate its validation rules.
            if (result.Validation.Findings.Any(f => f.Code == "invalid_workflow_state" && f.Field == "request"))
                return BadRequest(new { message = "Invalid recommendation validation request." });
            // Service operational failure is not a completed domain validation.
            if (result.Validation.Findings.Any(f => f.Code == "backend_unavailable")) return ServerFailure();
            return Ok(result);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception)
        {
            // Never return exception text, stack traces, or provider/database details.
            return ServerFailure();
        }
    }

    private ObjectResult ServerFailure() => Problem(statusCode: StatusCodes.Status500InternalServerError,
        title: "Unable to validate the recommendation.");
}

// Run before ApiController's automatic ModelStateInvalidFilter (-2000). Binding and
// DataAnnotations still run normally, but attempted values/parser details are not echoed.
[AttributeUsage(AttributeTargets.Class)]
internal sealed class SanitizedRecommendationRequestAttribute : ActionFilterAttribute
{
    public SanitizedRecommendationRequestAttribute() => Order = -2001;

    public override void OnActionExecuting(ActionExecutingContext context)
    {
        if (!context.ModelState.IsValid)
            context.Result = new BadRequestObjectResult(new { message = "Invalid recommendation validation request." });
    }
}
