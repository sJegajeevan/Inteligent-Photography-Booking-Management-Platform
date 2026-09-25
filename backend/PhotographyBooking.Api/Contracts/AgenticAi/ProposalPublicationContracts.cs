using System.Text.Json.Serialization;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

// Internal application boundary, not an anonymous publication command. No owner/new version/JSON input.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class ProposalPublicationRequest
{
    public required Guid WorkflowId { get; init; }
    // Optimistic precondition only. The server allocates the next version under lock.
    public required int ExpectedProposalVersion { get; init; }
    public required CustomerPhotographyRequirements Requirements { get; init; }
    public required RecommendationSelection Selection { get; init; }
    public required FinalValidationResult Evidence { get; init; }
    public required string TimeZoneId { get; init; }
    public required bool IsReservation { get; init; }
}

public sealed record ProposalPublicationResult(FinalValidationClassification Classification,
    string? ErrorCode, FinalRecommendationProposal? Proposal);
