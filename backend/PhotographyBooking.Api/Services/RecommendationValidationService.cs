using System.ComponentModel.DataAnnotations;
using PhotographyBooking.Api.Contracts.AgenticAi;

namespace PhotographyBooking.Api.Services;

/// <summary>Read-only backend validation for future tools. No authorization grant or booking write capability.</summary>
public sealed class RecommendationValidationService(PhotographyPackageService packages,
    PackagePriceCalculationService prices, BookingSlotValidationService slots)
{
    // today must be supplied by the backend's clock, never by the model/tool request.
    public async Task<RecommendationCheck> CheckAsync(RecommendationSelection selection, DateOnly today,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(selection);
        var errors = new List<ValidationResult>();
        Validator.TryValidateObject(selection, new ValidationContext(selection), errors, true);
        if (selection.Customization is not null)
        {
            Validator.TryValidateObject(selection.Customization, new ValidationContext(selection.Customization), errors, true);
            if (selection.Customization.SelectedAddonIds is null)
                errors.Add(new ValidationResult("Supply an add-on selection list."));
        }
        if (errors.Count > 0) return Fail("InvalidSelection", string.Join(" ", errors.Select(e => e.ErrorMessage)));
        var timeError = BookingSlotRules.ValidateTime(selection.Date, selection.StartTime, selection.EndTime, today);
        if (timeError is not null) return Fail("InvalidTime", timeError);

        ct.ThrowIfCancellationRequested();
        var package = await packages.GetPublicAsync(selection.StudioId, selection.PackageId);
        if (package is null) return Fail("PackageUnavailable", "Select an active package belonging to this studio.");
        if (!BookingSlotRules.FitsPackageDuration(package.DurationHours, selection.Customization!.ExtraHours,
                selection.StartTime, selection.EndTime))
            return Fail("DurationExceeded", "The booking must fit within the package duration plus purchased extra hours.");
        var slot = await slots.CheckAsync(selection.StudioId, selection.Date, selection.StartTime, selection.EndTime, today, ct);
        if (!slot.IsAvailable) return Fail(slot.Code.ToString(), slot.Error!);

        var pricing = await prices.CalculatePublicAsync(selection.StudioId, selection.PackageId, selection.Customization);
        if (pricing.Result is null) return Fail("InvalidPricing", pricing.Error ?? "Unable to calculate the package price.");
        var priceError = BookingSlotRules.ValidateBookingTotal(pricing.Result.FinalPrice);
        if (priceError is not null) return Fail("InvalidPricing", priceError);
        ct.ThrowIfCancellationRequested();
        return new(new(ValidationOutcome.Pass, [], DateTimeOffset.UtcNow), pricing.Result);
    }

    private static RecommendationCheck Fail(string code, string message) =>
        new(new(ValidationOutcome.Fail, [new(code, "selection", FindingSeverity.Error, message)], DateTimeOffset.UtcNow), null);
}
