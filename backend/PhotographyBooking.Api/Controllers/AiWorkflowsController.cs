using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Controllers;

[ApiController, Authorize, SanitizedWorkflowRequest]
[Route("api/ai-workflows")]
[RequestSizeLimit(16384)]
public sealed class AiWorkflowsController(AiWorkflowService workflows) : ControllerBase
{
    [HttpPost]
    public Task<IActionResult> Create([FromBody] CreateAiWorkflowRequest request, CancellationToken ct) => Guard(async () =>
    {
        var result = await workflows.CreateAsync(request, User, ct);
        return CreatedAtAction(nameof(Get), new { workflowId = result.Id }, result);
    });

    [HttpGet("{workflowId}")]
    public Task<IActionResult> Get([FromRoute] Guid workflowId, CancellationToken ct) =>
        Guard(async () => Ok(await workflows.GetAsync(workflowId, User, ct)));

    [HttpGet]
    public Task<IActionResult> List([FromQuery] AiWorkflowListRequest request, CancellationToken ct) =>
        Guard(async () => Ok(await workflows.ListAsync(request, User, ct)));

    [HttpPost("{workflowId}/approve")]
    public Task<IActionResult> Approve([FromRoute] Guid workflowId, [FromBody] ApproveAiWorkflowRequest request, CancellationToken ct) =>
        Guard(() => Decide(workflowId, request.ProposalVersion, AiApprovalDecision.Approved, null, ct));

    [HttpPost("{workflowId}/reject")]
    public Task<IActionResult> Reject([FromRoute] Guid workflowId, [FromBody] RejectAiWorkflowRequest request, CancellationToken ct) =>
        Guard(() => Decide(workflowId, request.ProposalVersion, AiApprovalDecision.Rejected, request.Reason, ct));

    private async Task<IActionResult> Decide(Guid id, int version, AiApprovalDecision decision, string? reason, CancellationToken ct)
    {
        var result = await workflows.DecideAsync(id, version, decision, reason, User, ct);
        if (result.Error is null)
            return Ok(new AiWorkflowDecisionResponse(id, version, result.Status?.ToString(), null));
        if (result.Status == AiWorkflowStatus.RevalidationRequired)
            return Ok(new AiWorkflowDecisionResponse(id, version, "RevalidationRequired", SafeDomainCode(result.Error)));
        return result.Error switch
        {
            "Forbidden" or "NotFound" => Error(404, "not_found"),
            "InvalidDecision" or "ReasonTooLong" or "ReasonRequired" => Error(400, "invalid_request"),
            "StaleProposal" => Error(409, "stale_proposal"),
            "AlreadyDecided" or "NotAwaitingApproval" => Error(409, "already_decided_or_not_awaiting_approval"),
            "Expired" => Error(409, "expired_proposal"),
            "IncompleteProposal" or "InvalidPackageStudio" or "invalid_workflow_state" => Error(409, "invalid_proposal"),
            "validation_failed" or "budget_failure" => Error(409, "validation_failed"),
            "price_changed" or "stale_recommendation" or "slot_unavailable" or "booking_conflict" => Error(409, SafeDomainCode(result.Error)),
            _ => ServerFailure()
        };
    }

    private static string SafeDomainCode(string code) => code is "price_changed" or "stale_recommendation" or
        "slot_unavailable" or "booking_conflict" or "budget_failure" ? code : "validation_failed";

    private async Task<IActionResult> Guard(Func<Task<IActionResult>> action)
    {
        if (!ModelState.IsValid) return Error(400, "invalid_request");
        try { return await action(); }
        catch (OperationCanceledException) { throw; }
        catch (AiWorkflowApiFailure error)
        {
            return error.Code switch { "unauthenticated" => Error(401, "unauthenticated"),
                "not_found" => Error(404, "not_found"), "invalid_request" => Error(400, "invalid_request"), _ => ServerFailure() };
        }
        catch (DbUpdateConcurrencyException) { return Error(409, "concurrency_conflict"); }
        catch (Exception error) when (IsConflict(error)) { return Error(409, "concurrency_conflict"); }
        catch (Exception) { return ServerFailure(); }
    }

    private static bool IsConflict(Exception error) => error is PostgresException { SqlState: "40001" or "40P01" or "23505" } ||
        error is DbUpdateException { InnerException: PostgresException { SqlState: "40001" or "40P01" or "23505" } };
    private ObjectResult Error(int status, string code) => StatusCode(status, new { errorCode = code });
    private ObjectResult ServerFailure() => Problem(statusCode: 500, title: "Unable to process the workflow request.");
}

[AttributeUsage(AttributeTargets.Class)]
internal sealed class SanitizedWorkflowRequestAttribute : ActionFilterAttribute
{
    public SanitizedWorkflowRequestAttribute() => Order = -2001;
    public override void OnActionExecuting(ActionExecutingContext context)
    {
        if (!context.ModelState.IsValid)
            context.Result = new BadRequestObjectResult(new { errorCode = "invalid_request" });
    }
}
