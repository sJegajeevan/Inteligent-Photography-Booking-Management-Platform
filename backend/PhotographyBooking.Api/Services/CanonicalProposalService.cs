using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

/// <summary>Shared deterministic foundation; caller owns authorization, locking and persistence.</summary>
public sealed class CanonicalProposalService(FinalRecommendationValidationService validation, TimeProvider clock)
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        NumberHandling = JsonNumberHandling.Strict
    };
    internal static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Json);
    internal static bool Same<T>(T left, T right) => Serialize(left) == Serialize(right);

    // Stored canonical documents must roundtrip exactly, including read-only safety flags.
    internal static T Read<T>(string json)
    {
        var value = JsonSerializer.Deserialize<T>(json, Json) ?? throw new JsonException();
        if (!JsonNode.DeepEquals(JsonNode.Parse(json), JsonNode.Parse(Serialize(value)))) throw new JsonException();
        using var doc = JsonDocument.Parse(json);
        CheckKeys(doc.RootElement);
        return value;
    }
    private static void CheckKeys(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!keys.Add(property.Name)) throw new JsonException();
                CheckKeys(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) CheckKeys(item);
    }

    internal static bool ValidEvidence(FinalValidationResult? evidence, RecommendationSelection selection, DateTimeOffset now, bool requireFresh = true)
    {
        var current = evidence?.Current;
        return evidence is not null && evidence.Classification == FinalValidationClassification.Pass &&
            evidence.Validation is not null && evidence.Validation.Outcome == ValidationOutcome.Pass &&
            evidence.Validation.Findings is { Count: 0 } && current?.Pricing is not null &&
            Same(current.Selection, selection) && current.IncludedServices is not null &&
            current.PackageDurationHours > 0 && current.RequiredDurationHours == current.PackageDurationHours + selection.Customization.ExtraHours &&
            current.Pricing.PackageId == selection.PackageId && current.Pricing.ExtraHours == selection.Customization.ExtraHours &&
            current.Pricing.AdditionalPhotographers == selection.Customization.AdditionalPhotographers &&
            current.Pricing.SelectedAddons is { Count: 0 } &&
            evidence.CheckedAtUtc.Offset == TimeSpan.Zero && evidence.CheckedAtUtc <= now &&
            evidence.Validation.CheckedAtUtc == evidence.CheckedAtUtc &&
            evidence.EvidenceExpiresAtUtc.Offset == TimeSpan.Zero && (!requireFresh || evidence.EvidenceExpiresAtUtc > now) &&
            evidence.EvidenceExpiresAtUtc - evidence.CheckedAtUtc == FinalRecommendationValidationService.EvidenceLifetime;
    }

    internal static string Reason(FinalValidationResult result) => result.Validation.Findings
        .Select(f => f.Code).FirstOrDefault(c => c is "price_changed" or "stale_recommendation" or "slot_unavailable" or
            "booking_conflict" or "budget_failure" or "backend_unavailable" or "invalid_workflow_state") ?? "validation_failed";

    private Task<FinalValidationResult> CheckAsync(CustomerPhotographyRequirements requirements,
        RecommendationSelection selection, FinalValidationResult evidence, CancellationToken ct) => validation.CheckAsync(new()
    {
        Requirements = requirements, Selection = selection, TimeZoneId = "Asia/Colombo",
        PriorEvidence = new() { Selection = selection, QuotedFinalPrice = evidence.Current!.Pricing!.FinalPrice,
            PackageDurationHours = evidence.Current.PackageDurationHours, IncludedServices = evidence.Current.IncludedServices,
            CheckedAtUtc = evidence.CheckedAtUtc, SlotWasAvailable = true }
    }, ct);

    public async Task<ProposalPublicationResult> PrepareAsync(AiWorkflow workflow, ProposalPublicationRequest input, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        CustomerPhotographyRequirements stored;
        try
        {
            input = Read<ProposalPublicationRequest>(Serialize(input));
            stored = Read<CustomerPhotographyRequirements>(workflow.NormalizedRequirementsJson);
            if (input.WorkflowId != workflow.Id || workflow.CustomerId <= 0 || input.ExpectedProposalVersion != workflow.ProposalVersion ||
                workflow.ProposalVersion < 0 || workflow.ProposalVersion == int.MaxValue ||
                workflow.Status is not (AiWorkflowStatus.Validation or AiWorkflowStatus.RevalidationRequired or AiWorkflowStatus.AwaitingApproval) ||
                !Same(stored, input.Requirements) || input.IsReservation || input.TimeZoneId != "Asia/Colombo" ||
                input.Selection?.Customization is null || !ValidEvidence(input.Evidence, input.Selection, clock.GetUtcNow(), requireFresh: false))
                return new(FinalValidationClassification.Fail, "invalid_workflow_state", null);
        }
        catch (Exception error) when (error is JsonException or NotSupportedException or ArgumentException or NullReferenceException)
        { return new(FinalValidationClassification.Fail, "invalid_workflow_state", null); }

        var fresh = await CheckAsync(stored, input.Selection, input.Evidence, ct);
        if (fresh.Classification != FinalValidationClassification.Pass)
            return new(fresh.Classification, Reason(fresh), null);
        if (!ValidEvidence(fresh, input.Selection, clock.GetUtcNow()))
            return new(FinalValidationClassification.Fail, "invalid_backend_response", null);
        var proposal = new FinalRecommendationProposal(Guid.NewGuid(), checked(workflow.ProposalVersion + 1),
            stored, fresh.Current!.Selection, fresh.Current.Pricing!, fresh.Validation, fresh.CheckedAtUtc,
            fresh.EvidenceExpiresAtUtc, "Recommendation verified by current backend checks.") { FinalEvidence = fresh };
        return new(FinalValidationClassification.Pass, null, proposal);
    }

    public async Task<ProposalPublicationResult> RevalidateApprovalAsync(AiWorkflow workflow, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        FinalRecommendationProposal proposal;
        try
        {
            proposal = Read<FinalRecommendationProposal>(workflow.FinalProposalJson!);
            var now = clock.GetUtcNow();
            if (proposal.ProposalId == Guid.Empty || proposal.Version != workflow.ProposalVersion ||
                proposal.Selection.StudioId != workflow.SelectedStudioId || proposal.Selection.PackageId != workflow.SelectedPackageId ||
                proposal.ExpiresAtUtc.UtcDateTime != workflow.ExpiresAt || proposal.CreatedAtUtc != proposal.FinalEvidence?.CheckedAtUtc ||
                proposal.ExpiresAtUtc != proposal.FinalEvidence.EvidenceExpiresAtUtc ||
                !Same(proposal.Requirements, Read<CustomerPhotographyRequirements>(workflow.NormalizedRequirementsJson)) ||
                !Same(proposal.Pricing, proposal.FinalEvidence.Current?.Pricing) ||
                !Same(proposal.Validation, proposal.FinalEvidence.Validation) ||
                !ValidEvidence(proposal.FinalEvidence, proposal.Selection, now))
                return new(FinalValidationClassification.Fail, "invalid_workflow_state", null);
        }
        catch (Exception error) when (error is JsonException or NotSupportedException or ArgumentException or NullReferenceException)
        { return new(FinalValidationClassification.Fail, "invalid_workflow_state", null); }
        var fresh = await CheckAsync(proposal.Requirements, proposal.Selection, proposal.FinalEvidence!, ct);
        if (fresh.Classification != FinalValidationClassification.Pass)
            return new(fresh.Classification, Reason(fresh), null);
        if (!ValidEvidence(fresh, proposal.Selection, clock.GetUtcNow()) || proposal.ExpiresAtUtc <= clock.GetUtcNow())
            return new(FinalValidationClassification.RevalidationRequired, "stale_recommendation", null);
        return new(FinalValidationClassification.Pass, null, proposal);
    }
}
