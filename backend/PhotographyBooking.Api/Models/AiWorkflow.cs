namespace PhotographyBooking.Api.Models;

public enum AiWorkflowStatus
{
    Submitted, StudioMatching, PackageRecommendation, Scheduling, Validation,
    AwaitingApproval, Approved, Rejected, NeedsInput, Failed, Cancelled, Expired, RevalidationRequired
}

/// <summary>Recommendation state only. This aggregate has no Booking relationship or write action.</summary>
public sealed class AiWorkflow
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int CustomerId { get; set; }
    public User Customer { get; set; } = null!;
    public AiWorkflowStatus Status { get; set; } = AiWorkflowStatus.Submitted;
    // Serialize validated Phase 1 contracts, never raw model messages, prompts, credentials or GPS.
    public string NormalizedRequirementsJson { get; set; } = string.Empty;
    public string CurrentStep { get; set; } = "Submitted";
    public string? FinalProposalJson { get; set; }
    public int ProposalVersion { get; set; }
    public Guid? SelectedStudioId { get; set; }
    public Studio? SelectedStudio { get; set; }
    public Guid? SelectedPackageId { get; set; }
    public PhotographyPackage? SelectedPackage { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
    // Npgsql maps this to PostgreSQL's existing xmin system column; no extra schema column.
    public uint RowVersion { get; set; }
    public List<AiWorkflowEvent> Events { get; set; } = [];
    public List<AiWorkflowApproval> Approvals { get; set; } = [];
}
