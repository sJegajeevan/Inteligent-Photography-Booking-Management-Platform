using System.ComponentModel.DataAnnotations;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.DTOs.Scheduling;

public sealed class SchedulingCandidateRequestDto : IValidatableObject
{
    // Inclusive days, not the difference between the endpoints.
    public const int MaximumDateRangeDays = 31;
    public DateOnly EarliestDate { get; init; }
    public DateOnly LatestDate { get; init; }
    public TimeOnly? PreferredStartTime { get; init; }
    public TimeOnly? PreferredEndTime { get; init; }
    public decimal CoverageHours { get; init; }
    public string TimeZoneId { get; init; } = "Asia/Colombo";
    [Required] public PackagePriceCalculationRequestDto Customization { get; init; } = new();

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (EarliestDate == default || LatestDate == default || LatestDate < EarliestDate ||
            LatestDate.DayNumber - EarliestDate.DayNumber >= MaximumDateRangeDays)
            yield return new("Supply an ordered date range of at most 31 inclusive days.", [nameof(EarliestDate), nameof(LatestDate)]);
        if (PreferredStartTime.HasValue != PreferredEndTime.HasValue || PreferredStartTime >= PreferredEndTime)
            yield return new("Supply both preferred times in increasing order, or neither.", [nameof(PreferredStartTime), nameof(PreferredEndTime)]);
        if (CoverageHours <= 0 || CoverageHours > 24)
            yield return new("Coverage must be greater than zero and at most 24 hours.", [nameof(CoverageHours)]);
        if (TimeZoneId != "Asia/Colombo")
            yield return new("Only Asia/Colombo is supported.", [nameof(TimeZoneId)]);
        if (Customization is null) yield break; // Required attribute handles null.
        var errors = new List<ValidationResult>();
        Validator.TryValidateObject(Customization, new ValidationContext(Customization), errors, true);
        foreach (var error in errors) yield return error;
        if (Customization.SelectedAddonIds is null ||
            Customization.SelectedAddonIds.Distinct().Count() != Customization.SelectedAddonIds.Count)
            yield return new("Supply a non-null add-on list without duplicates.", [nameof(Customization)]);
        if (Customization.SelectedAddonIds?.Count > 0 || Customization.AdditionalPhotographers != 0)
            yield return new("Scheduling currently supports no add-ons and zero additional photographers.", [nameof(Customization)]);
    }
}
