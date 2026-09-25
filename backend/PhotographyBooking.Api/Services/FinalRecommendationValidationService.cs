using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;

namespace PhotographyBooking.Api.Services;

/// <summary>Fresh read-only validation. No publication, approval, reservation, or workflow/booking writes.</summary>
public sealed class FinalRecommendationValidationService
{
    public static readonly TimeSpan EvidenceLifetime = TimeSpan.FromMinutes(5);
    private static readonly TimeZoneInfo BusinessZone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Colombo");
    private static readonly JsonSerializerOptions StrictJson = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, NumberHandling = JsonNumberHandling.Strict };
    private readonly TimeProvider _clock;
    private readonly Func<RecommendationSelection, DateOnly, CancellationToken,
        Task<(PhotographyPackageResponseDto? Package, RecommendationCheck Check)>> _read;

    public FinalRecommendationValidationService(ApplicationDbContext db, PhotographyPackageService packages,
        RecommendationValidationService validation, PackagePriceCalculationService prices, TimeProvider clock) : this(clock,
        async (selection, today, ct) =>
        {
            // A single snapshot across the existing services, never held across an AI call.
            // No SaveChanges, SQL writes, or reservation locks. Booking creation keeps its own locks.
            await using var transaction = await BeginOwnedTransactionAsync(db.Database.CurrentTransaction,
                () => db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, ct));
            var package = await packages.GetPublicAsync(selection.StudioId, selection.PackageId);
            var check = await validation.CheckAsync(selection, today, ct);
            // The existing validator stops at the first slot failure. Still obtain a fresh quote
            // for active packages so price/budget changes are reported independently of conflicts.
            if (package is not null && check.Pricing is null)
            {
                var pricing = await prices.CalculatePublicAsync(selection.StudioId, selection.PackageId, selection.Customization);
                check = check with { Pricing = pricing.Result };
            }
            if (transaction is not null) await transaction.CommitAsync(ct);
            return (package, check);
        }) { }

    // Null means the caller owns commit/rollback/disposal. Never nest or commit its transaction.
    internal static async Task<IDbContextTransaction?> BeginOwnedTransactionAsync(IDbContextTransaction? current,
        Func<Task<IDbContextTransaction>> begin) => current is null ? await begin() : null;

    // Offline checks supply read-only callbacks; production always uses the services above.
    internal FinalRecommendationValidationService(TimeProvider clock,
        Func<RecommendationSelection, DateOnly, CancellationToken,
            Task<(PhotographyPackageResponseDto? Package, RecommendationCheck Check)>> read)
    { _clock = clock; _read = read; }

    public async Task<FinalValidationResult> CheckAsync(FinalValidationRequest request, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        var checkedAt = _clock.GetUtcNow();
        var findings = new List<ValidationFinding>();
        var classification = FinalValidationClassification.Pass;
        CurrentRecommendationEvidence? current = null;
        var timestampAvailable = false;
        void Add(string code, string field, string message, bool revalidate = false)
        {
            findings.Add(new(code, field, FindingSeverity.Error, message));
            if (!revalidate) classification = FinalValidationClassification.Fail;
            else if (classification != FinalValidationClassification.Fail) classification = FinalValidationClassification.RevalidationRequired;
        }
        FinalValidationResult Result() => new(classification,
            new(classification == FinalValidationClassification.Pass ? ValidationOutcome.Pass : ValidationOutcome.Fail,
                findings, checkedAt), current, checkedAt, checkedAt.Add(EvidenceLifetime), timestampAvailable);
        bool Valid(object? value) => value is not null && Validator.TryValidateObject(value, new(value), [], true);
        bool ValidSelection(RecommendationSelection? selection) => Valid(selection) && Valid(selection!.Customization) &&
            selection.StartTime < selection.EndTime &&
            selection.Customization.SelectedAddonIds is not null &&
            selection.Customization.SelectedAddonIds.Count == selection.Customization.SelectedAddonIds.Distinct().Count();

        // Snapshot all nested mutable values before awaits, validating the actual internal contract recursively.
        try
        {
            if (request is null) throw new JsonException();
            request = JsonSerializer.Deserialize<FinalValidationRequest>(JsonSerializer.Serialize(request, StrictJson), StrictJson)!;
        }
        catch (Exception error) when (error is JsonException or NotSupportedException or ArgumentException)
        {
            Add("invalid_workflow_state", "request", "Supply complete structured recommendation evidence.");
            return Result();
        }
        var prior = request.PriorEvidence;
        var selection = request.Selection;
        var requirements = request.Requirements;
        if (!Valid(requirements) || requirements.RequestedServices is null ||
            string.IsNullOrWhiteSpace(requirements.PhotographyType) || string.IsNullOrWhiteSpace(requirements.Location) ||
            !ValidSelection(selection) || prior is null || !ValidSelection(prior.Selection) ||
            prior.QuotedFinalPrice < 0 || prior.QuotedFinalPrice > 9999999999999999.99m ||
            prior.PackageDurationHours is <= 0 or > 24 ||
            (prior.IncludedServices is not null && (prior.IncludedServices.Any(s => s is null || s.Id == Guid.Empty || string.IsNullOrWhiteSpace(s.ServiceName)) ||
                prior.IncludedServices.Select(s => s.Id).Distinct().Count() != prior.IncludedServices.Count)))
        {
            Add("invalid_workflow_state", "request", "Supply valid requirements, selection, and prior evidence.");
            return Result();
        }
        var customization = selection.Customization;
        var previous = prior.Selection;
        if (selection.StudioId != previous.StudioId || selection.PackageId != previous.PackageId || selection.Date != previous.Date ||
            selection.StartTime != previous.StartTime || selection.EndTime != previous.EndTime ||
            customization.ExtraHours != previous.Customization.ExtraHours ||
            customization.AdditionalPhotographers != previous.Customization.AdditionalPhotographers ||
            !customization.SelectedAddonIds.Order().SequenceEqual(previous.Customization.SelectedAddonIds.Order()))
        {
            Add("invalid_workflow_state", "selection", "Selection or customization differs from the trusted recommendation.");
            return Result();
        }
        if (request.TimeZoneId != "Asia/Colombo" || customization.SelectedAddonIds.Count != 0 || customization.AdditionalPhotographers != 0)
            Add("validation_failed", "constraints", "Unsupported timezone or customization policy.");
        var localNow = TimeZoneInfo.ConvertTime(checkedAt, BusinessZone);
        var today = DateOnly.FromDateTime(localNow.DateTime);
        if (BookingSlotRules.ValidateTime(selection.Date, selection.StartTime, selection.EndTime, today) is not null ||
            selection.Date == today && selection.StartTime < TimeOnly.FromDateTime(localNow.DateTime))
            Add(prior.SlotWasAvailable ? "stale_recommendation" : "validation_failed", "selection", "Selected interval is invalid or has elapsed.", prior.SlotWasAvailable);
        if (selection.Date < requirements.EarliestDate || selection.Date > requirements.LatestDate ||
            requirements.PreferredStartTime is { } preferredStart && selection.StartTime < preferredStart ||
            requirements.PreferredEndTime is { } preferredEnd && selection.EndTime > preferredEnd)
            Add("validation_failed", "selection", "Selected interval is outside requested dates or preferred times.");
        timestampAvailable = prior.CheckedAtUtc.HasValue;
        if (prior.CheckedAtUtc is { } priorTime)
        {
            if (priorTime.Offset != TimeSpan.Zero || priorTime > checkedAt)
                Add("invalid_workflow_state", "priorEvidence", "Prior check timestamp must be valid UTC evidence.");
            else if (checkedAt - priorTime >= EvidenceLifetime)
                Add("stale_recommendation", "priorEvidence", "Prior evidence has expired; request renewed recommendations.", true);
        }
        if (classification == FinalValidationClassification.Fail) return Result();

        PhotographyPackageResponseDto? package;
        RecommendationCheck check;
        try { (package, check) = await _read(selection, today, ct); }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception)
        {
            Add("backend_unavailable", "validation", "Unable to complete fresh backend validation.");
            return Result();
        }
        ct.ThrowIfCancellationRequested();
        if (package is null || package.Status != "Active")
        {
            Add("stale_recommendation", "package", "Previously recommended package is no longer available.", true);
            return Result();
        }
        if (package.Id != selection.PackageId || package.StudioId != selection.StudioId)
        {
            Add("validation_failed", "package", "Package does not belong to the selected studio.");
            return Result();
        }
        var services = package.Services.Select(s => new FinalServiceEvidence(s.Id, s.ServiceName)).ToArray();
        var serviceNames = services.Select(s => s.ServiceName.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var servicesChanged = prior.IncludedServices is not null && !prior.IncludedServices.OrderBy(s => s.Id)
            .Select(s => (s.Id, s.ServiceName.Trim().ToUpperInvariant())).SequenceEqual(services.OrderBy(s => s.Id)
                .Select(s => (s.Id, s.ServiceName.Trim().ToUpperInvariant())));
        if (requirements.RequestedServices.Any(s => !serviceNames.Contains(s.Trim())))
            Add(servicesChanged ? "stale_recommendation" : "validation_failed", "services",
                "Current package does not include every requested service.", servicesChanged);
        if (servicesChanged)
            Add("stale_recommendation", "services", "Package service evidence changed.", true);
        var durationChanged = prior.PackageDurationHours.HasValue && prior.PackageDurationHours != package.DurationHours;
        if (durationChanged) Add("stale_recommendation", "duration", "Package duration changed.", true);
        // Reject invalid current data before addition/conversion; don't truncate fractional coverage.
        if (package.DurationHours <= 0 || package.DurationHours > 24 || customization.ExtraHours > 24 ||
            package.DurationHours + customization.ExtraHours > 24)
        {
            Add(durationChanged ? "stale_recommendation" : "validation_failed", "duration", "Purchased duration is unsupported.", durationChanged);
            return Result();
        }
        var requiredDuration = package.DurationHours + customization.ExtraHours;
        var requiredTicks = (long)decimal.Ceiling(requiredDuration * TimeSpan.TicksPerHour);
        if (requiredDuration < requirements.CoverageHours || selection.EndTime.Ticks - selection.StartTime.Ticks != requiredTicks)
            Add(durationChanged ? "stale_recommendation" : "validation_failed", "duration",
                "Selected interval must equal full purchased duration and cover requested hours.", durationChanged);
        foreach (var finding in check.Validation.Findings.Where(f => f.Severity == FindingSeverity.Error))
        {
            var (code, revalidate) = finding.Code switch
            {
                "Unavailable" => (prior.SlotWasAvailable ? "slot_unavailable" : "validation_failed", prior.SlotWasAvailable),
                "Conflict" or "Duplicate" => (prior.SlotWasAvailable ? "booking_conflict" : "validation_failed", prior.SlotWasAvailable),
                "PackageUnavailable" => ("stale_recommendation", true),
                "InvalidTime" when prior.SlotWasAvailable => ("stale_recommendation", true),
                "DurationExceeded" when durationChanged => ("stale_recommendation", true),
                _ => ("validation_failed", false)
            };
            // Map codes only; don't forward arbitrary service error text or private data.
            Add(code, "selection", "Fresh backend selection checks did not pass.", revalidate);
        }
        if (check.Validation.Outcome != ValidationOutcome.Pass && check.Validation.Findings.All(f => f.Severity != FindingSeverity.Error))
            Add("validation_failed", "selection", "Fresh backend validation did not pass.");
        var price = check.Pricing;
        if (price is not null)
        {
            if (price.PackageId != selection.PackageId || price.ExtraHours != customization.ExtraHours ||
                price.AdditionalPhotographers != customization.AdditionalPhotographers || price.SelectedAddons.Count != 0 ||
                BookingSlotRules.ValidateBookingTotal(price.FinalPrice) is not null)
            {
                Add("validation_failed", "pricing", "Current pricing evidence is inconsistent.");
                price = null;
            }
            else
            {
                var priceChanged = price.FinalPrice != prior.QuotedFinalPrice;
                if (priceChanged) Add("price_changed", "pricing", "Authoritative final price changed; renewed review is required.", true);
                if (price.FinalPrice > requirements.MaximumBudget || requirements.MinimumBudget is { } minimum && price.FinalPrice < minimum)
                    Add("budget_failure", "pricing", "Current authoritative price is outside the requested budget.", priceChanged);
            }
        }
        else if (check.Validation.Outcome == ValidationOutcome.Pass)
            Add("validation_failed", "pricing", "Current authoritative pricing is missing.");
        current = new(selection, package.DurationHours, requiredDuration, services, price);
        var finishedAt = _clock.GetUtcNow();
        var finishedLocal = TimeZoneInfo.ConvertTime(finishedAt, BusinessZone);
        var finishedDate = DateOnly.FromDateTime(finishedLocal.DateTime);
        if (finishedAt - checkedAt >= EvidenceLifetime || selection.Date < finishedDate ||
            selection.Date == finishedDate && selection.StartTime < TimeOnly.FromDateTime(finishedLocal.DateTime))
            Add("stale_recommendation", "selection", "Evidence or selected interval elapsed during validation.", true);
        // Timestamp is the snapshot start, not a claim that concurrent changes cannot have happened since.
        return Result();
    }
}
