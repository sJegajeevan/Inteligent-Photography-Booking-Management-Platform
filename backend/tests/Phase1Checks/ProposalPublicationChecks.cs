using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class ProposalPublicationChecks
{
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now = new(2026, 9, 21, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Transaction : IDbContextTransaction
    {
        public Guid TransactionId { get; } = Guid.NewGuid();
        public bool Disposed;
        public void Commit() { }
        public Task CommitAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public void Rollback() { }
        public Task RollbackAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public void Dispose() => Disposed = true;
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }

    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool ok, string name) { if (!ok) throw new Exception("FAILED publication: " + name); count++; }
        var clock = new Clock();
        var studioId = Guid.NewGuid(); var packageId = Guid.NewGuid(); var serviceId = Guid.NewGuid();
        var date = new DateOnly(2026, 9, 22);
        var requirements = new CustomerPhotographyRequirements { PhotographyType = "Wedding", Location = "Jaffna",
            MaximumBudget = 100000, CoverageHours = 4, EarliestDate = date, LatestDate = date, RequestedServices = ["Photography"] };
        var selection = new RecommendationSelection { StudioId = studioId, PackageId = packageId, Date = date,
            StartTime = new(8, 0), EndTime = new(12, 0) };
        var price = 80000m; var active = true; string? slotError = null;
        var reads = 0;
        var validator = new FinalRecommendationValidationService(clock, (selected, today, ct) =>
        {
            ct.ThrowIfCancellationRequested(); reads++;
            var package = new PhotographyPackageResponseDto { Id = packageId, StudioId = studioId,
                Status = active ? "Active" : "Inactive", DurationHours = 4,
                Services = [new() { Id = serviceId, ServiceName = "Photography" }] };
            var findings = slotError is null ? Array.Empty<ValidationFinding>() :
                [new ValidationFinding(slotError, "selection", FindingSeverity.Error, "PRIVATE booking/customer detail")];
            return Task.FromResult<(PhotographyPackageResponseDto?, RecommendationCheck)>((package,
                new(new(slotError is null ? ValidationOutcome.Pass : ValidationOutcome.Fail, findings, clock.Now),
                    new PackagePriceCalculationResponseDto { PackageId = packageId, BasePrice = price, FinalPrice = price })));
        });
        var canonical = new CanonicalProposalService(validator, clock);
        var prior = await validator.CheckAsync(new() { Requirements = requirements, Selection = selection,
            PriorEvidence = new() { Selection = selection, QuotedFinalPrice = price, PackageDurationHours = 4,
                IncludedServices = [new(serviceId, "Photography")], CheckedAtUtc = clock.Now, SlotWasAvailable = true } });
        AiWorkflow Workflow() => new() { CustomerId = 73, NormalizedRequirementsJson = CanonicalProposalService.Serialize(requirements),
            Status = AiWorkflowStatus.Validation, CurrentStep = "Validation", CreatedAt = clock.Now.UtcDateTime.AddMinutes(-1),
            UpdatedAt = clock.Now.UtcDateTime, ExpiresAt = clock.Now.UtcDateTime.AddHours(1) };
        ProposalPublicationRequest Request(AiWorkflow w, FinalValidationResult? evidence = null, int? expected = null) => new()
        { WorkflowId = w.Id, ExpectedProposalVersion = expected ?? w.ProposalVersion, Requirements = requirements,
            Selection = selection, Evidence = evidence ?? prior, TimeZoneId = "Asia/Colombo", IsReservation = false };
        var workflow = Workflow();
        var result = await canonical.PrepareAsync(workflow, Request(workflow));
        Check(result.Classification == FinalValidationClassification.Pass && result.Proposal?.Version == 1, "server initial version 1");
        Check(workflow.FinalProposalJson is null && workflow.Approvals.Count == 0, "preparation is side effect free");
        Check(AiWorkflowPublicationService.ApplyResult(workflow, result, clock.Now.UtcDateTime), "apply publication");
        Check(workflow.Status == AiWorkflowStatus.AwaitingApproval && workflow.CurrentStep == "HumanApproval", "durable state/step");
        Check(workflow.CustomerId == 73 && workflow.NormalizedRequirementsJson == CanonicalProposalService.Serialize(requirements), "stored ownership/requirements unchanged");
        Check(workflow.ProposalVersion == 1 && workflow.SelectedPackageId == packageId && workflow.SelectedStudioId == studioId, "selection columns/version");
        Check(workflow.ExpiresAt == prior.EvidenceExpiresAtUtc.UtcDateTime, "server expiry shrinks longer workflow lifetime");
        Check(result.Proposal!.RequiresHumanApproval && !result.Proposal.IsReservation && result.Proposal.FinalEvidence is not null, "canonical flags/evidence");
        Check(workflow.Events.Single().EventType == "ProposalPublished" && workflow.Approvals.Count == 0, "publication event without approval");
        Check(!workflow.FinalProposalJson!.Contains("PRIVATE"), "sanitized canonical proposal");
        var published = workflow.FinalProposalJson;
        Check((await canonical.RevalidateApprovalAsync(workflow)).Classification == FinalValidationClassification.Pass, "fresh reviewed proposal approval permitted");
        var revision = await canonical.PrepareAsync(workflow, Request(workflow));
        Check(revision.Proposal?.Version == 2, "revision increments exactly one");
        Check((await canonical.PrepareAsync(workflow, Request(workflow, expected: 9))).Proposal is null, "client cannot choose next version");
        Check(!typeof(ProposalPublicationRequest).GetProperties().Any(p => p.Name is "CustomerId" or "ProposalJson" or "Version"), "no owner JSON or new-version input");
        var readsBefore = reads;
        workflow.NormalizedRequirementsJson = CanonicalProposalService.Serialize(new CustomerPhotographyRequirements
            { PhotographyType = "Portrait", Location = "Colombo", MaximumBudget = 10000, CoverageHours = 1, EarliestDate = date, LatestDate = date });
        Check((await canonical.PrepareAsync(workflow, Request(workflow))).ErrorCode == "invalid_workflow_state", "requirements mismatch");
        workflow.NormalizedRequirementsJson = CanonicalProposalService.Serialize(requirements);
        foreach (var input in new[] { Request(workflow, prior with { Classification = FinalValidationClassification.Fail }),
            Request(workflow, prior with { EvidenceExpiresAtUtc = clock.Now.AddHours(1) }),
            Request(workflow, prior with { Current = null }), Request(workflow, prior with { CheckedAtUtc = clock.Now.AddMinutes(1) }) })
            Check((await canonical.PrepareAsync(workflow, input)).Proposal is null, "invalid input no publication");
        Check(reads == readsBefore, "structural failures before reads");
        foreach (var field in new[] { "isReservation", "timeZoneId" })
        {
            var json = JsonNode.Parse(CanonicalProposalService.Serialize(Request(workflow)))!;
            json[field] = field == "isReservation" ? JsonValue.Create(true) : JsonValue.Create("UTC");
            var altered = CanonicalProposalService.Read<ProposalPublicationRequest>(json.ToJsonString());
            Check((await canonical.PrepareAsync(workflow, altered)).ErrorCode == "invalid_workflow_state", "input safety flag " + field);
        }
        var originalTime = clock.Now;
        clock.Now = clock.Now.AddMinutes(6);
        var stale = await canonical.PrepareAsync(workflow, Request(workflow));
        Check(stale.Classification == FinalValidationClassification.RevalidationRequired && stale.ErrorCode == "stale_recommendation",
            "expired prior evidence requires revalidation");
        var staleWorkflow = Workflow(); staleWorkflow.FinalProposalJson = published; staleWorkflow.ProposalVersion = 1;
        Check(AiWorkflowPublicationService.ApplyResult(staleWorkflow, stale, clock.Now.UtcDateTime) &&
            staleWorkflow.Status == AiWorkflowStatus.RevalidationRequired && staleWorkflow.CurrentStep == "Validation" &&
            staleWorkflow.FinalProposalJson == published && staleWorkflow.ProposalVersion == 1 && staleWorkflow.Approvals.Count == 0,
            "stale publication retains reviewed JSON/version and creates no decision");
        clock.Now = originalTime;
        foreach (var (error, expected) in new[] { ("price", "price_changed"), ("Unavailable", "slot_unavailable"),
            ("Conflict", "booking_conflict"), ("inactive", "stale_recommendation") })
        {
            price = error == "price" ? 90000 : 80000;
            active = error != "inactive";
            slotError = error is "Unavailable" or "Conflict" ? error : null;
            result = await canonical.PrepareAsync(workflow, Request(workflow));
            Check(result.Classification == FinalValidationClassification.RevalidationRequired && result.ErrorCode == expected && result.Proposal is null, "publication revalidates " + error);
            var approval = await canonical.RevalidateApprovalAsync(workflow);
            Check(approval.Classification == FinalValidationClassification.RevalidationRequired && approval.ErrorCode == expected, "approval revalidates " + error);
            Check(workflow.FinalProposalJson == published && workflow.Approvals.Count == 0, "reviewed content not silently replaced " + error);
        }
        price = 80000; active = true; slotError = null;
        foreach (var change in new Action<JsonNode>[] {
            n => n["version"] = 9, n => n["expiresAtUtc"] = clock.Now.AddHours(2).ToString("O"),
            n => n["selection"]!["studioId"] = Guid.NewGuid().ToString(),
            n => n["selection"]!["packageId"] = Guid.NewGuid().ToString(),
            n => n["isReservation"] = true, n => n["requiresHumanApproval"] = false,
            n => n["finalEvidence"] = null, n => n["unknown"] = "PRIVATE", n => n["pricing"]!["finalPrice"] = 1 })
        {
            var json = JsonNode.Parse(published!)!; change(json); workflow.FinalProposalJson = json.ToJsonString();
            Check((await canonical.RevalidateApprovalAsync(workflow)).ErrorCode == "invalid_workflow_state", "malformed stored canonical evidence");
        }
        workflow.FinalProposalJson = "PRIVATE invalid JSON";
        Check((await canonical.RevalidateApprovalAsync(workflow)).ErrorCode == "invalid_workflow_state", "malformed stored JSON");
        workflow.FinalProposalJson = published;
        Check(AiWorkflowApprovalRules.CanReview("Studio", 1, 1) && !AiWorkflowApprovalRules.CanReview("Studio", 2, 1), "studio ownership");
        Check(AiWorkflowApprovalRules.CanReview("Admin", 2, 1) && !AiWorkflowApprovalRules.CanReview("Customer", 1, 1), "admin/customer policies");
        Check(AiWorkflowApprovalRules.Validate(workflow, 1, AiApprovalDecision.Rejected, "No", clock.Now.UtcDateTime) is null &&
            AiWorkflowApprovalRules.ResultingStatus(AiApprovalDecision.Rejected) == AiWorkflowStatus.Rejected, "rejection rules preserved");
        Check(AiWorkflowApprovalRules.Validate(workflow, 2, AiApprovalDecision.Approved, null, clock.Now.UtcDateTime) == "StaleProposal", "stale reviewer version");
        using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql().Options);
        Check(db.Model.FindEntityType(typeof(AiWorkflow))!.FindProperty("RowVersion")!.IsConcurrencyToken, "xmin preserved");
        Check(db.Model.FindEntityType(typeof(AiWorkflowApproval))!.GetIndexes().Any(i => i.IsUnique &&
            i.Properties.Select(p => p.Name).SequenceEqual(new[] { "WorkflowId", "ProposalVersion" })), "unique decision preserved");
        db.Attach(workflow);
        AiWorkflowPublicationService.ApplyResult(workflow, revision, clock.Now.UtcDateTime);
        db.AiWorkflowEvents.Add(workflow.Events.Last());
        AiWorkflowPersistenceGuard.Validate(db.ChangeTracker);
        Check(workflow.ProposalVersion == 2 && workflow.CustomerId == 73, "revision passes persistence guard");
        Check(!db.ChangeTracker.Entries<Booking>().Any() && !db.ChangeTracker.Entries<AiWorkflowApproval>().Any(), "publication creates no booking or approval");
        Check(await new AiWorkflowApprovalService(db, canonical, clock).RecordAsync(workflow.Id, 2,
            AiApprovalDecision.Approved, null, new ClaimsPrincipal()) == "Forbidden", "anonymous blocked before database");
        var began = 0;
        var caller = new Transaction();
        Check(await FinalRecommendationValidationService.BeginOwnedTransactionAsync(caller, () =>
            { began++; return Task.FromResult<IDbContextTransaction>(new Transaction()); }) is null && began == 0 && !caller.Disposed,
            "caller transaction reused without nesting/disposal");
        await using (var owned = await FinalRecommendationValidationService.BeginOwnedTransactionAsync(null, () =>
            { began++; return Task.FromResult<IDbContextTransaction>(new Transaction()); }))
            Check(owned is not null && began == 1, "standalone transaction opened");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await canonical.PrepareAsync(workflow, Request(workflow), cancelled.Token); Check(false, "cancellation"); }
        catch (OperationCanceledException) { Check(true, "cancellation propagated"); }
        return count;
    }
}
