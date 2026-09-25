using System.Security.Claims;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Contracts.AgenticAi;

namespace PhotographyBooking.Api.Services;

public static class AiWorkflowApprovalRules
{
    internal static bool CanReview(string role, int reviewerId, int studioOwnerId) =>
        role == "Admin" || role == "Studio" && reviewerId == studioOwnerId;
    public static string? Validate(AiWorkflow workflow, int proposalVersion, AiApprovalDecision decision,
        string? reason, DateTime now)
    {
        if (!Enum.IsDefined(decision)) return "InvalidDecision";
        if (reason?.Length > 1000) return "ReasonTooLong";
        if (decision != AiApprovalDecision.Approved && string.IsNullOrWhiteSpace(reason)) return "ReasonRequired";
        if (workflow.ExpiresAt <= now) return "Expired";
        if (workflow.Status != AiWorkflowStatus.AwaitingApproval) return "NotAwaitingApproval";
        if (proposalVersion <= 0 || proposalVersion != workflow.ProposalVersion) return "StaleProposal";
        if (workflow.FinalProposalJson is null || workflow.SelectedStudioId is null || workflow.SelectedPackageId is null)
            return "IncompleteProposal";
        return null;
    }

    public static AiWorkflowStatus ResultingStatus(AiApprovalDecision decision) => decision switch
    {
        AiApprovalDecision.Approved => AiWorkflowStatus.Approved,
        AiApprovalDecision.Rejected => AiWorkflowStatus.Rejected,
        AiApprovalDecision.RevisionRequested => AiWorkflowStatus.RevalidationRequired,
        _ => throw new ArgumentOutOfRangeException(nameof(decision))
    };
}

/// <summary>Authenticated approval persistence boundary. Never creates a Booking.</summary>
public sealed class AiWorkflowApprovalService(ApplicationDbContext db, CanonicalProposalService canonical, TimeProvider clock)
{
    public async Task<string?> RecordAsync(Guid workflowId, int proposalVersion, AiApprovalDecision decision,
        string? reason, ClaimsPrincipal principal, CancellationToken ct = default)
        => (await RecordDecisionAsync(workflowId, proposalVersion, decision, reason, principal, ct)).Error;

    public async Task<AiWorkflowDecisionResult> RecordDecisionAsync(Guid workflowId, int proposalVersion, AiApprovalDecision decision,
        string? reason, ClaimsPrincipal principal, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        if (principal.Identity?.IsAuthenticated != true ||
            !int.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var reviewerId)) return new("Forbidden", null);
        var reviewer = await db.Users.AsNoTracking().SingleOrDefaultAsync(u => u.Id == reviewerId, ct);
        if (reviewer is null || !principal.IsInRole(reviewer.Role) || reviewer.Role is not ("Studio" or "Admin")) return new("Forbidden", null);

        await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.RepeatableRead, ct);
        // The locks serialize competing approvals and selected-studio ownership changes.
        var workflows = await db.AiWorkflows.FromSqlInterpolated(
            $"SELECT *, xmin FROM public.\"AiWorkflows\" WHERE \"Id\" = {workflowId} FOR UPDATE").ToListAsync(ct);
        var workflow = workflows.SingleOrDefault();
        if (workflow is null) return new("NotFound", null);
        if (workflow.SelectedStudioId is null) return new("NotFound", null);
        var studios = await db.Studios.FromSqlInterpolated(
            $"SELECT * FROM public.\"Studios\" WHERE \"Id\" = {workflow.SelectedStudioId.Value} FOR SHARE")
            .AsNoTracking().ToListAsync(ct);
        var studio = studios.SingleOrDefault();
        if (studio is null || !AiWorkflowApprovalRules.CanReview(reviewer.Role, reviewerId, studio.UserId)) return new("NotFound", null);
        var now = clock.GetUtcNow().UtcDateTime;
        var error = AiWorkflowApprovalRules.Validate(workflow, proposalVersion, decision, reason, now);
        if (error is not null) return new(error, null);
        if (await db.AiWorkflowApprovals.AnyAsync(a => a.WorkflowId == workflowId && a.ProposalVersion == proposalVersion, ct))
            return new("AlreadyDecided", null);
        if (!await db.PhotographyPackages.AnyAsync(p => p.Id == workflow.SelectedPackageId && p.StudioId == studio.Id, ct))
            return new("InvalidPackageStudio", null);

        if (decision == AiApprovalDecision.Approved)
        {
            var check = await canonical.RevalidateApprovalAsync(workflow, ct);
            if (check.Classification != FinalValidationClassification.Pass)
            {
                if (check.Classification == FinalValidationClassification.RevalidationRequired)
                {
                    workflow.Status = AiWorkflowStatus.RevalidationRequired;
                    workflow.CurrentStep = "Validation";
                    workflow.UpdatedAt = clock.GetUtcNow().UtcDateTime;
                    db.AiWorkflowEvents.Add(new AiWorkflowEvent { WorkflowId = workflow.Id,
                        EventType = "ApprovalRevalidationRequired", StepName = "HumanApproval",
                        Summary = "Reviewed proposal requires revalidation.", Success = false, CreatedAt = workflow.UpdatedAt,
                        DetailsJson = JsonSerializer.Serialize(new { proposalVersion, errorCode = check.ErrorCode }) });
                    await db.SaveChangesAsync(ct);
                    await transaction.CommitAsync(ct);
                }
                return new(check.ErrorCode ?? "validation_failed", check.Classification == FinalValidationClassification.RevalidationRequired
                    ? AiWorkflowStatus.RevalidationRequired : null);
            }
            now = clock.GetUtcNow().UtcDateTime;
            if (workflow.ExpiresAt <= now) return new("Expired", null);
        }

        db.AiWorkflowApprovals.Add(new AiWorkflowApproval {
            WorkflowId = workflowId, ProposalVersion = proposalVersion, ReviewerUserId = reviewerId,
            Decision = decision, ProposalSnapshotJson = workflow.FinalProposalJson!,
            Reason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim(), CreatedAt = now
        });
        workflow.Status = AiWorkflowApprovalRules.ResultingStatus(decision);
        workflow.CurrentStep = decision == AiApprovalDecision.RevisionRequested ? "Validation" : "Completed";
        workflow.UpdatedAt = now;
        db.AiWorkflowEvents.Add(new AiWorkflowEvent {
            WorkflowId = workflowId, EventType = "HumanDecisionRecorded", StepName = "HumanApproval",
            Summary = $"Human decision: {decision}.", // Fixed template, never a model trace/exception or reviewer free text.
            DetailsJson = JsonSerializer.Serialize(new { proposalVersion }), Success = true, CreatedAt = now
        });
        // Approval, status and event commit atomically; unique index and xmin are final race guards.
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return new(null, workflow.Status);
    }
}
