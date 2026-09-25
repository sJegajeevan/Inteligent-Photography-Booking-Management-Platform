using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

// Contracts only: no EF entities, agent execution, persistence or booking commands.
// Future model outputs are untrusted suggestions. Resolve IDs/evidence and validate nested objects at the tool boundary.
// ExplanationSummary is a short user-facing justification, never chain-of-thought.
public sealed record StudioMatch(Guid StudioId, string ExplanationSummary, IReadOnlyList<string> EvidenceIds);
public sealed record StudioMatchingOutput(IReadOnlyList<StudioMatch> RankedStudios, IReadOnlyList<string> UnmetPreferences);

public sealed record PackageRecommendation(Guid StudioId, Guid PackageId,
    PackagePriceCalculationRequestDto Customization, string ExplanationSummary, IReadOnlyList<string> EvidenceIds);
public sealed record PackageRecommendationOutput(IReadOnlyList<PackageRecommendation> RankedPackages);

public sealed record ProposedSlot(Guid StudioId, Guid PackageId, DateOnly Date, TimeOnly StartTime,
    TimeOnly EndTime, string ExplanationSummary, IReadOnlyList<string> EvidenceIds);
public sealed record SchedulingOutput(IReadOnlyList<ProposedSlot> RankedSlots, IReadOnlyList<string> UnmetPreferences);

[JsonConverter(typeof(JsonStringEnumConverter<ValidationOutcome>))]
public enum ValidationOutcome { Pass, NeedsInput, Fail }
[JsonConverter(typeof(JsonStringEnumConverter<FindingSeverity>))]
public enum FindingSeverity { Warning, Error }
public sealed record ValidationFinding(string Code, string Field, FindingSeverity Severity, string Message);
public sealed record ValidationSafetyOutput(ValidationOutcome Outcome, IReadOnlyList<ValidationFinding> Findings,
    DateTimeOffset CheckedAtUtc);

/// <summary>Read-only selection check. Customer identity, prices and availability are not accepted from callers.</summary>
public sealed class RecommendationSelection : IValidatableObject
{
    public Guid StudioId { get; init; }
    public Guid PackageId { get; init; }
    public DateOnly Date { get; init; }
    public TimeOnly StartTime { get; init; }
    public TimeOnly EndTime { get; init; }
    [Required] public PackagePriceCalculationRequestDto Customization { get; init; } = new();

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (StudioId == Guid.Empty) yield return new("Select a valid studio.", [nameof(StudioId)]);
        if (PackageId == Guid.Empty) yield return new("Select a valid package.", [nameof(PackageId)]);
        if (Date == default) yield return new("Select a valid date.", [nameof(Date)]);
    }
}

/// <summary>ASP.NET-generated evidence. Point-in-time only; does not reserve inventory or authorize a booking.</summary>
public sealed record RecommendationCheck(ValidationSafetyOutput Validation, PackagePriceCalculationResponseDto? Pricing);

/// <summary>Assembled by ASP.NET after verifying suggestions. Never bind this as a trusted model/customer command.</summary>
public sealed record FinalRecommendationProposal(Guid ProposalId, int Version,
    CustomerPhotographyRequirements Requirements, RecommendationSelection Selection,
    PackagePriceCalculationResponseDto Pricing, ValidationSafetyOutput Validation,
    DateTimeOffset CreatedAtUtc, DateTimeOffset ExpiresAtUtc, string ExplanationSummary)
{
    public FinalValidationResult? FinalEvidence { get; init; }
    public int SchemaVersion => 1;
    public bool RequiresHumanApproval => true;
    public bool IsReservation => false;
}
