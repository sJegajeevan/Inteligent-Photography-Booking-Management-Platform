using System.Security.Claims;
using System.Text.Json;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class JourneyExecutionChecks
{
    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool condition, string name) { if (!condition) throw new Exception("Journey: " + name); count++; }
        async Task Reject(Func<Task> action, string name)
        {
            try { await action(); } catch (AiWorkflowApiFailure) { Check(true, name); return; }
            throw new Exception("Journey accepted: " + name);
        }
        var f = new Fixture();
        var first = await f.Start();
        Check(f.Calls.SequenceEqual(["StudioMatching"]), "initial request executes only matching");
        Check(first.Proposal is null && first.Journey!.Options.Count == 2, "real studio options, no proposal");
        Check(f.Stored!.SelectedStudioId is null && f.Stored.Approvals.Count == 0, "no approval or booking selection on start");
        var duplicate = await f.Start();
        Check(f.Calls.Count == 1 && duplicate.Id == first.Id, "initial operation replay resumes without execution");
        await Reject(() => f.Service.GetAsync(first.Id, new ClaimsPrincipal(new ClaimsIdentity()), default), "anonymous customer cannot resume");
        await Reject(() => f.Service.GetAsync(first.Id, Fixture.User(99), default), "customer role claim must match authoritative account");
        await Reject(() => f.Service.GetAsync(first.Id, Fixture.User(2), default), "other customer cannot read");
        await Reject(() => f.Service.ActAsync(first.Id, "studio", f.Command(first, first.Journey!.Options[0].EventId), Fixture.User(2), default), "other customer cannot select");
        await Reject(() => f.Action(first, "package", Guid.NewGuid()), "no packages before studio selection");
        await Reject(() => f.Action(first, "schedule", Guid.NewGuid()), "no scheduling before package selection");
        await Reject(() => f.Action(first, "submit"), "no submit before validation");
        await Reject(() => f.Action(first, "studio", Guid.NewGuid()), "arbitrary studio option rejected");
        f.StudioAvailable = false;
        await Reject(() => f.Action(first, "studio", first.Journey!.Options[0].EventId), "deleted studio rejected authoritatively");
        f.StudioAvailable = true;
        var selection = f.Command(first, first.Journey!.Options[0].EventId);
        var second = await f.Service.ActAsync(first.Id, "studio", selection, Fixture.User(1), default);
        Check(f.Calls.SequenceEqual(["StudioMatching", "PackageRecommendation"]), "studio selection runs only packages");
        Check(second.Journey!.Options.Where(o => o.Stage == "PackageRecommendation").All(o => o.StudioId == f.Studio), "packages belong to selected studio");
        Check(second.Journey.ScheduleOptionId is null && second.Proposal is null, "no validation before schedule selection");
        await f.Service.ActAsync(first.Id, "studio", selection, Fixture.User(1), default);
        Check(f.Calls.Count == 2, "selection replay never reruns agent");
        await Reject(() => f.Action(first, "studio", first.Journey.Options[1].EventId), "stale revision rejected");
        var packageOption = second.Journey.Options.First(o => o.Stage == "PackageRecommendation");
        f.PackageAvailable = false;
        await Reject(() => f.Action(second, "package", packageOption.EventId), "unavailable selected package rejected");
        f.PackageAvailable = true;
        var third = await f.Action(second, "package", packageOption.EventId);
        Check(f.Calls.Last() == "Scheduling" && f.Calls.Count == 3, "package selection runs scheduling only");
        Check(third.Journey!.Options.Single(o => o.Stage == "Scheduling").StartTime!.StartsWith("10:00:00"), "schedule from authoritative candidates");
        var fourth = await f.Action(third, "schedule", third.Journey.Options.Single(o => o.Stage == "Scheduling").EventId);
        Check(f.Calls.SequenceEqual(JourneyState.Stages), "one execution of each agent after inputs");
        Check(fourth.Journey!.Validated && fourth.Status == "Validation" && fourth.Proposal!.Pricing.FinalPrice == 5000, "validated canonical customer draft with authoritative price");
        Check(f.Stored!.Approvals.Count == 0 && f.Stored.Status != AiWorkflowStatus.AwaitingApproval, "validation does not submit or approve");

        var changedSchedule = await f.Action(fourth, "schedule", fourth.Journey.ScheduleOptionId);
        Check(changedSchedule.Journey!.Revision == fourth.Journey.Revision + 1 && changedSchedule.Proposal!.Version > fourth.Proposal!.Version,
            "schedule change invalidates validation and produces a new proposal version");
        var changedPackage = await f.Action(changedSchedule, "package", changedSchedule.Journey.PackageOptionId);
        Check(changedPackage.Proposal is null && !changedPackage.Journey!.Validated && changedPackage.Journey.ScheduleOptionId is null,
            "package change invalidates schedule selection and validation, hides historical proposal");
        var changedStudio = await f.Action(changedPackage, "studio", changedPackage.Journey!.Options.First(o => o.Stage == "StudioMatching" && o.StudioId != f.Studio).EventId);
        Check(changedStudio.Proposal is null && changedStudio.Journey!.PackageOptionId is null && changedStudio.Journey.ScheduleOptionId is null &&
            changedStudio.Journey.Options.All(o => o.Stage != "Scheduling"), "studio change invalidates every downstream selection and result");

        var failed = new Fixture { FailureStage = "PackageRecommendation" };
        var fs = await failed.Start();
        fs = await failed.Action(fs, "studio", fs.Journey!.Options[0].EventId);
        Check(fs.Status == "Failed" && fs.Journey!.ErrorCode == "execution_unavailable" && failed.Calls.Count == 2, "failed stage persisted safely and later stages blocked");
        await Reject(() => failed.Action(fs, "package", Guid.NewGuid()), "cannot continue failed stage without options");
        failed.FailureStage = null;
        fs = await failed.Action(fs, "retry");
        Check(fs.Journey!.ErrorCode is null && failed.Calls.Last() == "PackageRecommendation" && failed.Calls.Count == 3, "stage-specific retry resumes without rerunning matching");
        Check(!JsonSerializer.Serialize(failed.Stored).Contains("PRIVATE"), "provider detail never persisted");

        var foreign = new Fixture { ForeignPackage = true };
        var bad = await foreign.Start();
        bad = await foreign.Action(bad, "studio", bad.Journey!.Options[0].EventId);
        Check(bad.Status == "Failed" && bad.Journey!.Options.All(o => o.Stage != "PackageRecommendation"), "foreign package result rejected");
        var unavailable = new Fixture { BadSlot = true };
        var us = await unavailable.Start();
        us = await unavailable.Action(us, "studio", us.Journey!.Options[0].EventId);
        us = await unavailable.Action(us, "package", us.Journey!.Options.First(o => o.Stage == "PackageRecommendation").EventId);
        Check(us.Status == "Failed" && us.Journey!.Options.All(o => o.Stage != "Scheduling"), "model schedule outside authoritative candidates rejected");

        var priceChanged = new Fixture { ChangePriceAfterValidation = true };
        var invalidFinal = await priceChanged.Ready();
        Check(invalidFinal.Status == "Failed" && invalidFinal.Proposal is null && invalidFinal.Journey!.ErrorCode == "price_changed",
            "fresh authoritative price overrides previous passing agent evidence");
        await Reject(() => priceChanged.Action(invalidFinal, "submit"), "failed final validation cannot submit");

        var approved = new Fixture();
        var ready = await approved.Ready();
        var before = approved.ValidationReads;
        var submit = approved.Command(ready);
        ready = await approved.Service.ActAsync(ready.Id, "submit", submit, Fixture.User(1), default);
        Check(ready.Status == "AwaitingApproval" && approved.ValidationReads > before, "explicit submit revalidates then enters owner queue");
        before = approved.ValidationReads;
        await approved.Service.ActAsync(ready.Id, "submit", submit, Fixture.User(1), default);
        Check(before == approved.ValidationReads && approved.Stored!.Events.Count(e => e.EventType == "JourneySubmittedForApproval") == 1,
            "duplicate submit is idempotent");
        Check(approved.Stored!.Approvals.Count == 0, "submission creates no approval or booking");
        await Reject(() => approved.Action(ready, "studio", ready.Journey!.StudioOptionId), "submitted workflow cannot be modified by customer");

        var concurrent = new Fixture();
        var initial = await concurrent.Start();
        concurrent.PauseNext = true;
        var action = concurrent.Command(initial, initial.Journey!.Options[0].EventId);
        var pending = concurrent.Service.ActAsync(initial.Id, "studio", action, Fixture.User(1), default);
        await concurrent.Entered.Task;
        var busy = await concurrent.Service.GetAsync(initial.Id, Fixture.User(1), default);
        Check(busy.Journey!.Busy && busy.Journey.Stage == "PackageRecommendation", "running stage is durably readable");
        await concurrent.Service.ActAsync(initial.Id, "studio", action, Fixture.User(1), default);
        Check(concurrent.Calls.Count == 2, "in-flight replay does not duplicate provider calls");
        await Reject(() => concurrent.Action(busy, "studio", busy.Journey.StudioOptionId), "concurrent different action blocked by claim");
        concurrent.Advance(TimeSpan.FromMinutes(5));
        var recovered = await concurrent.Action(busy, "retry");
        Check(!recovered.Journey!.Busy && recovered.Journey.Options.Any(o => o.Stage == "PackageRecommendation"), "abandoned claim can be retried after timeout");
        var retainedIds = recovered.Journey.Options.Select(o => o.EventId).ToArray();
        concurrent.Release.SetResult();
        var late = await pending;
        Check(late.Journey!.Options.Select(o => o.EventId).SequenceEqual(retainedIds) && late.Journey.Revision == recovered.Journey.Revision,
            "late completion cannot overwrite a newer revision");

        // Existing EF mapping is used offline to check that appending events marks inserts, not audit updates.
        var options = new Microsoft.EntityFrameworkCore.DbContextOptionsBuilder<PhotographyBooking.Api.Data.ApplicationDbContext>();
        Microsoft.EntityFrameworkCore.NpgsqlDbContextOptionsBuilderExtensions.UseNpgsql(options);
        using var db = new PhotographyBooking.Api.Data.ApplicationDbContext(options.Options);
        var aggregate = new AiWorkflow { CustomerId = 1 };
        db.Attach(aggregate);
        var ev = JourneyState.Append(aggregate, "StudioMatching", new() { Kind = "started", Revision = 1, Sequence = 1, OperationId = Guid.NewGuid() }, DateTime.UtcNow);
        AiJourneyService.TrackNewEvents(db, aggregate);
        PhotographyBooking.Api.Data.AiWorkflowPersistenceGuard.Validate(db.ChangeTracker);
        Check(db.Entry(ev).State == Microsoft.EntityFrameworkCore.EntityState.Added, "JourneyV1 append is an EF insert");
        return count + await JourneyStudioBoundaryChecks.RunAsync();
    }

    private sealed class FixedClock : TimeProvider
    {
        public TimeSpan Offset;
        public override DateTimeOffset GetUtcNow() => new DateTimeOffset(2030, 1, 1, 0, 0, 0, TimeSpan.Zero).Add(Offset);
    }

    private sealed class Fixture
    {
        public readonly Guid Studio = Guid.NewGuid(), OtherStudio = Guid.NewGuid(), Package = Guid.NewGuid(), Workflow = Guid.NewGuid();
        public AiWorkflow? Stored;
        public readonly List<string> Calls = [];
        public bool StudioAvailable = true, PackageAvailable = true, ForeignPackage, BadSlot;
        public bool ChangePriceAfterValidation;
        private decimal currentPrice = 5000;
        public string? FailureStage;
        public bool PauseNext;
        public readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Advance(TimeSpan time) => clock.Offset += time;
        public int ValidationReads;
        public readonly AiJourneyService Service;
        private readonly FixedClock clock = new();
        private readonly CustomerPhotographyRequirements requirements = new() { PhotographyType = "Portrait", Location = "Colombo", MaximumBudget = 10000,
            EarliestDate = new(2030, 1, 3), LatestDate = new(2030, 1, 3), CoverageHours = 2 };
        private PhotographyPackageResponseDto PackageDto(Guid studio) => new() { Id = Package, StudioId = studio, Name = "Portrait session", Status = "Active", DurationHours = 2 };
        private PackagePriceCalculationResponseDto Price() => new() { PackageId = Package, PackageName = "Portrait session", BasePrice = currentPrice, FinalPrice = currentPrice };
        private static AiWorkflow Clone(AiWorkflow w) => JsonSerializer.Deserialize<AiWorkflow>(JsonSerializer.Serialize(w))!;
        public static ClaimsPrincipal User(int id) => new(new ClaimsIdentity([new(ClaimTypes.NameIdentifier, id.ToString()), new(ClaimTypes.Role, "Customer")], "test"));
        public JourneyAction Command(AiWorkflowResponse w, Guid? option = null) => new() { OperationId = Guid.NewGuid(), Revision = w.Journey!.Revision, OptionEventId = option };
        public Task<AiWorkflowResponse> Start() => Service.CreateAsync(new() { Requirements = requirements, OperationId = Workflow }, User(1), default);
        public Task<AiWorkflowResponse> Action(AiWorkflowResponse w, string action, Guid? option = null) => Service.ActAsync(w.Id, action, Command(w, option), User(1), default);
        public async Task<AiWorkflowResponse> Ready()
        {
            var w = await Start();
            w = await Action(w, "studio", w.Journey!.Options[0].EventId);
            w = await Action(w, "package", w.Journey!.Options.First(o => o.Stage == "PackageRecommendation").EventId);
            return await Action(w, "schedule", w.Journey!.Options.First(o => o.Stage == "Scheduling").EventId);
        }

        public Fixture()
        {
            var validator = new FinalRecommendationValidationService(clock, (selection, today, ct) => {
                ValidationReads++;
                return Task.FromResult<(PhotographyPackageResponseDto?, RecommendationCheck)>((PackageDto(selection.StudioId),
                    new(new(ValidationOutcome.Pass, [], clock.GetUtcNow()), Price())));
            });
            var canonical = new CanonicalProposalService(validator, clock);
            Service = new(clock, (id, ct) => Task.FromResult(id is 1 or 2),
                (id, ct) => Task.FromResult(Stored?.Id == id ? Clone(Stored) : null),
                (id, ct) => Task.FromResult(StudioAvailable && (id == Studio || id == OtherStudio) ? new Studio { Id = id, StudioName = "Snap Studio", Location = "Colombo" } : null),
                (w, create, ct) => {
                    if (!create && w.RowVersion != Stored!.RowVersion) throw new Microsoft.EntityFrameworkCore.DbUpdateConcurrencyException();
                    w.RowVersion++;
                    Stored = Clone(w); return Task.CompletedTask;
                }, () => {},
                (sid, pid) => Task.FromResult(PackageAvailable && pid == Package ? PackageDto(sid) : null),
                (sid, pid, customization) => Task.FromResult<PackagePriceCalculationResponseDto?>(Price()),
                (sid, pid, request, ct) => Task.FromResult(new SchedulingCandidateResult(new(sid, pid, "Asia/Colombo", 2, 0, 2, clock.GetUtcNow(), false,
                    [new(Guid.NewGuid(), requirements.EarliestDate, new(10, 0), new(12, 0), ["authoritative-slot"])]))),
                canonical.PrepareAsync, canonical.RevalidateApprovalAsync,
                async (wid, operation, stage, input, ct) => {
                    Calls.Add(stage);
                    if (PauseNext) { PauseNext = false; Entered.SetResult(); await Release.Task; }
                    if (FailureStage == stage) throw new AiWorkflowApiFailure("execution_unavailable");
                    var state = JourneyState.Read(Stored!);
                    var sid = state.Selections.GetValueOrDefault("StudioMatching")?.Data.StudioId ?? Studio;
                    object output;
                    if (stage == "StudioMatching") output = new { rankedStudios = new[] {
                        new { studioId = Studio, explanationSummary = "Matches your photography needs." },
                        new { studioId = OtherStudio, explanationSummary = "Another matching studio." } } };
                    else if (stage == "PackageRecommendation") output = new { rankedPackages = new[] {
                        new { studioId = ForeignPackage ? Guid.NewGuid() : sid, packageId = Package, explanationSummary = "Includes requested coverage.",
                            customization = new { extraHours = 0 }, pricing = new { finalPrice = 5000 } } } };
                    else if (stage == "Scheduling") output = new { rankedSlots = new[] { new { studioId = sid, packageId = Package,
                        date = "2030-01-03", startTime = BadSlot ? "09:00:00" : "10:00:00", endTime = "12:00:00", explanationSummary = "Available session." } } };
                    else {
                        var selection = new RecommendationSelection { StudioId = sid, PackageId = Package, Date = requirements.EarliestDate, StartTime = new(10, 0), EndTime = new(12, 0) };
                        output = await validator.CheckAsync(new() { Requirements = requirements, Selection = selection,
                            PriorEvidence = new() { Selection = selection, QuotedFinalPrice = 5000, PackageDurationHours = 2,
                                CheckedAtUtc = clock.GetUtcNow(), SlotWasAvailable = true } }, ct);
                        if (ChangePriceAfterValidation) currentPrice = 6000;
                    }
                    return JsonSerializer.SerializeToElement(output, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                });
        }
    }
}
