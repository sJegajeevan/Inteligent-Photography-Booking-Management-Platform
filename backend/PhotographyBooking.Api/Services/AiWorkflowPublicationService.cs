using System.Data;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

/// <summary>Internal orchestration-only writer. No anonymous API, owner input, approval or booking writes.</summary>
public sealed class AiWorkflowPublicationService(ApplicationDbContext db, CanonicalProposalService canonical, TimeProvider clock)
{
    public async Task<ProposalPublicationResult> PublishAsync(ProposalPublicationRequest request, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        if (request is null || request.WorkflowId == Guid.Empty)
            return new(FinalValidationClassification.Fail, "invalid_workflow_state", null);
        // Snapshot mutable caller evidence before acquiring locks/awaiting IO.
        try { request = CanonicalProposalService.Read<ProposalPublicationRequest>(CanonicalProposalService.Serialize(request)); }
        catch (System.Text.Json.JsonException) { return new(FinalValidationClassification.Fail, "invalid_workflow_state", null); }
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, ct);
        var rows = await db.AiWorkflows.FromSqlInterpolated(
            $"SELECT *, xmin FROM public.\"AiWorkflows\" WHERE \"Id\" = {request.WorkflowId} FOR UPDATE").ToListAsync(ct);
        var workflow = rows.SingleOrDefault();
        if (workflow is null) return new(FinalValidationClassification.Fail, "invalid_workflow_state", null);
        // Submission orchestration may already track this entity; inspect the freshly locked row.
        await db.Entry(workflow).ReloadAsync(ct);
        var result = await canonical.PrepareAsync(workflow, request, ct);
        if (!ApplyResult(workflow, result, clock.GetUtcNow().UtcDateTime)) return result;
        db.AiWorkflowEvents.Add(workflow.Events.Last());
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return result;
    }

    internal static bool ApplyResult(AiWorkflow workflow, ProposalPublicationResult result, DateTime now)
    {
        if (result.Proposal is { } proposal)
        {
            workflow.FinalProposalJson = CanonicalProposalService.Serialize(proposal);
            workflow.ProposalVersion = proposal.Version;
            workflow.SelectedStudioId = proposal.Selection.StudioId;
            workflow.SelectedPackageId = proposal.Selection.PackageId;
            workflow.ExpiresAt = proposal.ExpiresAtUtc.UtcDateTime;
            workflow.Status = AiWorkflowStatus.AwaitingApproval;
            workflow.CurrentStep = "HumanApproval";
        }
        else if (result.Classification == FinalValidationClassification.RevalidationRequired)
        {
            workflow.Status = AiWorkflowStatus.RevalidationRequired;
            workflow.CurrentStep = "Validation";
        }
        else return false;
        workflow.UpdatedAt = now;
        workflow.Events.Add(new AiWorkflowEvent { WorkflowId = workflow.Id,
            EventType = result.Proposal is null ? "ProposalRevalidationRequired" : "ProposalPublished",
            StepName = "Validation", Summary = result.Proposal is null ? "Recommendation requires revalidation." : "Canonical proposal published.",
            Success = result.Proposal is not null, CreatedAt = workflow.UpdatedAt,
            DetailsJson = CanonicalProposalService.Serialize(new { proposalVersion = workflow.ProposalVersion, errorCode = result.ErrorCode }) });
        return true;
    }
}
