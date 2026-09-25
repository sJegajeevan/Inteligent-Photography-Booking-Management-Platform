using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class CreateAiWorkflowRequest
{
    [Required] public required CustomerPhotographyRequirements Requirements { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class ApproveAiWorkflowRequest
{
    [Range(1, int.MaxValue)] public required int ProposalVersion { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class RejectAiWorkflowRequest
{
    [Range(1, int.MaxValue)] public required int ProposalVersion { get; init; }
    [Required, StringLength(1000)] public required string Reason { get; init; }
}

public sealed class AiWorkflowListRequest : IValidatableObject
{
    [Range(1, 10000)] public int Page { get; init; } = 1;
    [Range(1, 100)] public int PageSize { get; init; } = 20;
    [StringLength(32)] public string? Status { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Status is not null && !Enum.GetNames<AiWorkflowStatus>().Contains(Status))
            yield return new("Invalid workflow status.", [nameof(Status)]);
    }
}

public sealed record AiWorkflowResponse(Guid Id, string Status, string CurrentStep, int ProposalVersion,
    Guid? SelectedStudioId, Guid? SelectedPackageId, FinalRecommendationProposal? Proposal,
    DateTime CreatedAt, DateTime UpdatedAt, DateTime ExpiresAt);
public sealed record AiWorkflowPage(IReadOnlyList<AiWorkflowResponse> Items, int Page, int PageSize, bool HasMore);
public sealed record AiWorkflowDecisionResponse(Guid WorkflowId, int ProposalVersion, string? Status, string? ErrorCode);

// Application result: status is explicit so HTTP adapters never infer a transition from an error string.
public sealed record AiWorkflowDecisionResult(string? Error, AiWorkflowStatus? Status);
