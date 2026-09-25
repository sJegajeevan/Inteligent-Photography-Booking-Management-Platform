using System.Text.Json.Serialization;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

// Internal trusted orchestration input, not an authenticated evidence token or a public command.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class FinalValidationRequest
{
    public required CustomerPhotographyRequirements Requirements { get; init; }
    public required RecommendationSelection Selection { get; init; }
    public required PriorRecommendationEvidence PriorEvidence { get; init; }
    // Requirements currently exposes a constant getter; explicitly validate the incoming zone here.
    public string TimeZoneId { get; init; } = "Asia/Colombo";
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class PriorRecommendationEvidence
{
    public required RecommendationSelection Selection { get; init; }
    public required decimal QuotedFinalPrice { get; init; }
    public decimal? PackageDurationHours { get; init; }
    public IReadOnlyList<FinalServiceEvidence>? IncludedServices { get; init; }
    public DateTimeOffset? CheckedAtUtc { get; init; }
    // Must be supplied by trusted orchestration, never inferred from a random slot/evidence ID.
    public bool SlotWasAvailable { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record FinalServiceEvidence(Guid Id, string ServiceName);

// Result classification, not a new workflow status or permission to publish/approve.
[JsonConverter(typeof(JsonStringEnumConverter<FinalValidationClassification>))]
public enum FinalValidationClassification { Pass, Fail, RevalidationRequired }

public sealed record CurrentRecommendationEvidence(RecommendationSelection Selection,
    decimal PackageDurationHours, decimal RequiredDurationHours, IReadOnlyList<FinalServiceEvidence> IncludedServices,
    PackagePriceCalculationResponseDto? Pricing);

public sealed record FinalValidationResult(FinalValidationClassification Classification,
    ValidationSafetyOutput Validation, CurrentRecommendationEvidence? Current,
    DateTimeOffset CheckedAtUtc, DateTimeOffset EvidenceExpiresAtUtc, bool PriorTimestampAvailable)
{
    public string TimeZoneId => "Asia/Colombo";
    public bool IsReservation => false;
}
