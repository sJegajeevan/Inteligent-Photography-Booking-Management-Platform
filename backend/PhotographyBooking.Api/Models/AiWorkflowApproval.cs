namespace PhotographyBooking.Api.Models;

public enum AiApprovalDecision { Approved, Rejected, RevisionRequested }

public sealed class AiWorkflowApproval
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid WorkflowId { get; set; }
    public AiWorkflow Workflow { get; set; } = null!;
    public int ProposalVersion { get; set; }
    public int ReviewerUserId { get; set; }
    public User Reviewer { get; set; } = null!;
    public AiApprovalDecision Decision { get; set; }
    // Preserve what was reviewed even after a revision replaces the workflow's current proposal.
    public string ProposalSnapshotJson { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
