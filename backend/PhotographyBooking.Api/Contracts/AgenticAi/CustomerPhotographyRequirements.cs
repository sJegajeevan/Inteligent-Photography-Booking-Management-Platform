using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

/// <summary>Customer input only. Identity comes from ASP.NET claims; precise GPS is not workflow state.</summary>
[System.Text.Json.Serialization.JsonUnmappedMemberHandling(System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow)]
public sealed class CustomerPhotographyRequirements : IValidatableObject
{
    public int SchemaVersion => 1;
    [Required, StringLength(100)] public string PhotographyType { get; init; } = string.Empty;
    [Required, StringLength(500)] public string Location { get; init; } = string.Empty;
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal? MinimumBudget { get; init; }
    [Range(typeof(decimal), "0", "9999999999999999.99")] public decimal MaximumBudget { get; init; }
    // Current prices are LKR and bookings are local dates/times. No implicit FX/timezone conversion.
    public string Currency => "LKR";
    public string TimeZoneId => "Asia/Colombo";
    public DateOnly EarliestDate { get; init; }
    public DateOnly LatestDate { get; init; }
    public TimeOnly? PreferredStartTime { get; init; }
    public TimeOnly? PreferredEndTime { get; init; }
    [Range(typeof(decimal), "0.01", "24")] public decimal CoverageHours { get; init; }
    [Required, MaxLength(20)] public IReadOnlyList<string> RequestedServices { get; init; } = [];
    [StringLength(1000)] public string? Notes { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (MinimumBudget > MaximumBudget)
            yield return new("Minimum budget must not exceed maximum budget.", [nameof(MinimumBudget), nameof(MaximumBudget)]);
        if (EarliestDate == default || LatestDate == default || LatestDate < EarliestDate)
            yield return new("Supply a valid, ordered date range.", [nameof(EarliestDate), nameof(LatestDate)]);
        if (PreferredStartTime.HasValue != PreferredEndTime.HasValue || PreferredStartTime >= PreferredEndTime)
            yield return new("Supply both preferred times in increasing order, or omit both.", [nameof(PreferredStartTime), nameof(PreferredEndTime)]);
        if (RequestedServices?.Any(value => string.IsNullOrWhiteSpace(value) || value.Length > 120) == true)
            yield return new("Service names must contain 1 to 120 characters.", [nameof(RequestedServices)]);
    }
}
