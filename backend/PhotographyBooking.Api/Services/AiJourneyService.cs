using System.Globalization;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.DTOs.Scheduling;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

/// <summary>Customer-owned event orchestration. xmin fences claims and completions; no transaction spans Python.</summary>
public interface IAiJourneyService
{
    Task<AiWorkflowResponse> CreateAsync(CreateAiWorkflowRequest request, ClaimsPrincipal user, CancellationToken ct);
    Task<AiWorkflowResponse> GetAsync(Guid id, ClaimsPrincipal user, CancellationToken ct);
    Task<AiWorkflowResponse> ActAsync(Guid id, string action, JourneyAction command, ClaimsPrincipal user, CancellationToken ct);
}

public sealed class AiJourneyService : IAiJourneyService
{
    private readonly TimeProvider clock;
    private readonly Func<int, CancellationToken, Task<bool>> customerExists;
    private readonly Func<Guid, CancellationToken, Task<AiWorkflow?>> read;
    private readonly Func<Guid, CancellationToken, Task<Studio?>> studioRead;
    private readonly Func<AiWorkflow, bool, CancellationToken, Task> save;
    private readonly Action clear;
    private readonly Func<Guid, Guid, Task<PhotographyPackageResponseDto?>> packageRead;
    private readonly Func<Guid, Guid, PackagePriceCalculationRequestDto, Task<PackagePriceCalculationResponseDto?>> priceRead;
    private readonly Func<Guid, Guid, SchedulingCandidateRequestDto, CancellationToken, Task<SchedulingCandidateResult>> discover;
    private readonly Func<AiWorkflow, ProposalPublicationRequest, CancellationToken, Task<ProposalPublicationResult>> prepare;
    private readonly Func<AiWorkflow, CancellationToken, Task<ProposalPublicationResult>> revalidate;
    private readonly Func<Guid, Guid, string, object, CancellationToken, Task<JsonElement>> run;

    public AiJourneyService(ApplicationDbContext db, InternalPythonWorkflowClient python,
        PhotographyPackageService packages, PackagePriceCalculationService prices, SchedulingCandidateService schedules,
        CanonicalProposalService canonical, TimeProvider clock) : this(clock,
        (id, ct) => db.Users.AnyAsync(u => u.Id == id && u.Role == "Customer", ct),
        (id, ct) => db.AiWorkflows.Include(w => w.Events).SingleOrDefaultAsync(w => w.Id == id, ct),
        (id, ct) => db.Studios.AsNoTracking().SingleOrDefaultAsync(s => s.Id == id, ct),
        async (w, create, ct) => {
            if (create) db.AiWorkflows.Add(w);
            else {
                TrackNewEvents(db, w);
                db.Entry(w).Property(x => x.UpdatedAt).IsModified = true;
            }
            await db.SaveChangesAsync(ct);
        }, db.ChangeTracker.Clear, packages.GetPublicAsync,
        async (sid, pid, customization) => (await prices.CalculatePublicAsync(sid, pid, customization)).Result,
        schedules.DiscoverAsync, canonical.PrepareAsync, canonical.RevalidateApprovalAsync, python.StageAsync) { }

    // Tests replace IO only. All ownership, stage, replay, selection and invalidation logic remains real.
    internal AiJourneyService(TimeProvider clock, Func<int, CancellationToken, Task<bool>> customerExists,
        Func<Guid, CancellationToken, Task<AiWorkflow?>> read, Func<Guid, CancellationToken, Task<Studio?>> studioRead,
        Func<AiWorkflow, bool, CancellationToken, Task> save, Action clear,
        Func<Guid, Guid, Task<PhotographyPackageResponseDto?>> packageRead,
        Func<Guid, Guid, PackagePriceCalculationRequestDto, Task<PackagePriceCalculationResponseDto?>> priceRead,
        Func<Guid, Guid, SchedulingCandidateRequestDto, CancellationToken, Task<SchedulingCandidateResult>> discover,
        Func<AiWorkflow, ProposalPublicationRequest, CancellationToken, Task<ProposalPublicationResult>> prepare,
        Func<AiWorkflow, CancellationToken, Task<ProposalPublicationResult>> revalidate,
        Func<Guid, Guid, string, object, CancellationToken, Task<JsonElement>> run)
    {
        this.clock = clock; this.customerExists = customerExists; this.read = read; this.studioRead = studioRead;
        this.save = save; this.clear = clear; this.packageRead = packageRead; this.priceRead = priceRead;
        this.discover = discover; this.prepare = prepare; this.revalidate = revalidate; this.run = run;
    }
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    internal static void TrackNewEvents(ApplicationDbContext db, AiWorkflow workflow)
    {
        // Entry() normally triggers local change detection. On an aggregate with a
        // tracked event, relationship fixup can discover new, pre-keyed events as
        // Modified before we can mark them Added. Register only detached events
        // first; never turn a modification of an existing audit event into an insert.
        var detect = db.ChangeTracker.AutoDetectChangesEnabled;
        try
        {
            db.ChangeTracker.AutoDetectChangesEnabled = false;
            foreach (var item in workflow.Events.Where(e => db.Entry(e).State == EntityState.Detached).ToArray())
                db.AiWorkflowEvents.Add(item);
        }
        finally { db.ChangeTracker.AutoDetectChangesEnabled = detect; }
    }

    private DateTime Now => clock.GetUtcNow().UtcDateTime;
    private static AiWorkflowApiFailure Fail(string code = "invalid_request") => new(code);

    private async Task<int> Customer(ClaimsPrincipal user, CancellationToken ct)
    {
        if (user.Identity?.IsAuthenticated != true) throw Fail("unauthenticated");
        if (!user.IsInRole("Customer") || !int.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ||
            !await customerExists(id, ct)) throw Fail("not_found");
        return id;
    }

    private async Task<AiWorkflow> Owned(Guid id, int customer, CancellationToken ct)
    {
        var workflow = await read(id, ct);
        return workflow?.CustomerId == customer ? workflow : throw Fail("not_found");
    }

    public async Task<AiWorkflowResponse> CreateAsync(CreateAiWorkflowRequest request, ClaimsPrincipal user, CancellationToken ct)
    {
        var customer = await Customer(user, ct);
        var requirements = AiWorkflowService.Normalize(request.Requirements);
        if (requirements.LatestDate.DayNumber - requirements.EarliestDate.DayNumber >= 31) throw Fail();
        if (request.OperationId == Guid.Empty) throw Fail();
        var id = request.OperationId ?? Guid.NewGuid();
        var existing = await read(id, ct);
        if (existing is not null)
        {
            if (existing.CustomerId != customer) throw Fail("not_found");
            if (existing.NormalizedRequirementsJson != CanonicalProposalService.Serialize(requirements) &&
                !CanonicalProposalService.Same(CanonicalProposalService.Read<CustomerPhotographyRequirements>(existing.NormalizedRequirementsJson), requirements))
                throw Fail("concurrency_conflict");
            return await Response(existing, ct);
        }
        var w = new AiWorkflow { Id = id, CustomerId = customer, NormalizedRequirementsJson = CanonicalProposalService.Serialize(requirements),
            CreatedAt = Now, UpdatedAt = Now, ExpiresAt = Now.AddHours(24), Status = AiWorkflowStatus.StudioMatching, CurrentStep = "StudioMatching" };
        JourneyState.Append(w, w.CurrentStep, new() { Kind = "started", Revision = 1, Sequence = 1, OperationId = id }, Now);
        await save(w, true, ct);
        await Execute(w.Id, customer, id, ct);
        return await GetAsync(id, user, ct);
    }

    public async Task<AiWorkflowResponse> GetAsync(Guid id, ClaimsPrincipal user, CancellationToken ct)
        => await Response(await Owned(id, await Customer(user, ct), ct), ct);

    public async Task<AiWorkflowResponse> ActAsync(Guid id, string action, JourneyAction command, ClaimsPrincipal user, CancellationToken ct)
    {
        var customer = await Customer(user, ct);
        var w = await Owned(id, customer, ct);
        var state = JourneyState.Read(w);
        if (command.OperationId == Guid.Empty || command.Revision < 1 || state.Entries.Count == 0 ||
            action is not ("studio" or "package" or "schedule" or "retry" or "submit")) throw Fail();
        if (w.Events.Any(e => e.Id == command.OperationId && e.EventType == "JourneySubmittedForApproval"))
        {
            if (action != "submit" || command.OptionEventId != null) throw Fail("concurrency_conflict");
            return await Response(w, ct);
        }
        var replay = state.Entries.FirstOrDefault(e => e.Data.OperationId == command.OperationId);
        if (replay is not null)
        {
            // Replays never dispatch an agent again. Reject a reused key with altered selection.
            if (command.OptionEventId != null && !state.Entries.Any(e => e.Data.OperationId == command.OperationId && e.Data.OptionEventId == command.OptionEventId))
                throw Fail("concurrency_conflict");
            return await Response(w, ct);
        }
        if (state.Revision != command.Revision || state.Revision >= 999999998 || state.Sequence > 999999980 ||
            w.Status is AiWorkflowStatus.AwaitingApproval or AiWorkflowStatus.Approved or AiWorkflowStatus.Rejected or AiWorkflowStatus.Cancelled)
            throw Fail("concurrency_conflict");
        if (state.Running is { } running && Now - running.Event.CreatedAt < TimeSpan.FromMinutes(4))
            throw Fail("stage_running");
        if (Now > w.CreatedAt.AddHours(24)) throw Fail("expired_proposal");

        var revision = state.Revision + 1;
        var sequence = state.Sequence;
        void Add(string stage, JourneyData data) => JourneyState.Append(w, stage, data with
        { Revision = revision, Sequence = ++sequence, OperationId = command.OperationId }, Now);

        if (action == "submit")
        {
            if (command.OptionEventId != null || state.Validated is null || state.Validated.Data.Revision != state.Revision ||
                w.Status != AiWorkflowStatus.Validation || w.FinalProposalJson is null || w.ExpiresAt <= Now)
                throw Fail("validation_required");
            // Fresh deterministic validation also occurs here; existing owner approval repeats it under its booking locks.
            var result = await revalidate(w, ct);
            if (result.Proposal is null) throw Fail(result.ErrorCode ?? "validation_required");
            w.Status = AiWorkflowStatus.AwaitingApproval;
            w.CurrentStep = "HumanApproval";
            // A bounded legacy event records submission, without adding a new JourneyV1 kind.
            w.Events.Add(new AiWorkflowEvent { Id = command.OperationId, WorkflowId = id, EventType = "JourneySubmittedForApproval", StepName = "HumanApproval",
                Summary = "Customer sent validated recommendation for studio approval.", Success = true, CreatedAt = Now });
            await Save(w, ct);
            return await Response(w, ct);
        }

        string next;
        if (action == "retry")
        {
            if (command.OptionEventId != null || state.ErrorCode is null && state.Running is null && state.Stage != "Validation") throw Fail("concurrency_conflict");
            next = state.Stage;
            Add(next, new() { Kind = "rewound", InvalidatesFrom = next });
        }
        else
        {
            var stage = action switch { "studio" => "StudioMatching", "package" => "PackageRecommendation", "schedule" => "Scheduling", _ => throw Fail() };
            var option = state.Options.GetValueOrDefault(stage)?.SingleOrDefault(o => o.Event.Id == command.OptionEventId) ?? throw Fail("stale_option");
            if (state.Running is not null) throw Fail("stage_running");
            await CheckOption(option, state, ct);
            next = JourneyState.Stages[Array.IndexOf(JourneyState.Stages, stage) + 1];
            var completion = state.Entries.Last(e => e.Event.StepName == stage && e.Data.Kind == "completed" && e.Data.OptionEventIds!.Contains(option.Event.Id));
            Add(stage, new() { Kind = "selected", SourceEventId = completion.Event.Id, OptionEventId = option.Event.Id, InvalidatesFrom = next });
        }
        Add(next, new() { Kind = "started", SourceEventId = command.OptionEventId });
        w.Status = Enum.Parse<AiWorkflowStatus>(next);
        w.CurrentStep = next;
        await Save(w, ct); // claim + invalidation + selection are one atomic EF save, guarded by xmin
        await Execute(id, customer, command.OperationId, ct);
        return await GetAsync(id, user, ct);
    }

    private async Task Save(AiWorkflow w, CancellationToken ct)
    {
        w.UpdatedAt = Now;
        // Force a workflow UPDATE even on coarse clocks so every event append uses the xmin concurrency fence.
        await save(w, false, ct);
    }

    private async Task CheckOption(JourneyEntry option, JourneyState state, CancellationToken ct)
    {
        var d = option.Data;
        if (d.StudioId is null || await studioRead(d.StudioId.Value, ct) is null) throw Fail("stale_option");
        if (option.Event.StepName != "StudioMatching")
        {
            if (!state.Selections.TryGetValue("StudioMatching", out var studio) || studio.Data.StudioId != d.StudioId ||
                await packageRead(d.StudioId!.Value, d.PackageId!.Value) is null) throw Fail("stale_option");
        }
        if (option.Event.StepName == "Scheduling" &&
            (!state.Selections.TryGetValue("PackageRecommendation", out var package) || package.Data.PackageId != d.PackageId)) throw Fail("stale_option");
    }

    private async Task Execute(Guid id, int customer, Guid operation, CancellationToken ct)
    {
        string stage = "StudioMatching";
        try
        {
            var w = await Owned(id, customer, ct);
            var state = JourneyState.Read(w);
            if (state.Running?.Data.OperationId != operation) return;
            stage = state.Stage;
            var requirements = CanonicalProposalService.Read<CustomerPhotographyRequirements>(w.NormalizedRequirementsJson);
            var input = await Input(state, requirements, operation, ct);
            var output = await run(id, operation, stage, input, ct);
            // Discard all tracked snapshots before persisting a completion. Late results cannot cross revisions.
            clear();
            w = await Owned(id, customer, ct);
            state = JourneyState.Read(w);
            if (state.Running?.Data.OperationId != operation) return;
            await Complete(w, state, output, requirements, ct);
            await Save(w, ct);
        }
        catch (Exception error) when (error is not DbUpdateException)
        {
            // Never persist exception messages, raw model responses, or provider state.
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            clear();
            var w = await Owned(id, customer, cleanup.Token);
            var state = JourneyState.Read(w);
            if (state.Running?.Data.OperationId != operation) return;
            var code = error is AiWorkflowApiFailure failure && AiExecutionFailure.ValidCode(failure.Code) ? failure.Code :
                error is OperationCanceledException ? "execution_timeout" : "invalid_execution_response";
            JourneyState.Append(w, stage, new() { Kind = "failed", Revision = state.Revision, Sequence = state.Sequence + 1,
                OperationId = operation, ErrorCode = code }, Now);
            w.Status = AiWorkflowStatus.Failed;
            await Save(w, cleanup.Token);
        }
    }

    private static decimal Number(string value) => decimal.Parse(value, Invariant);
    private static string DecimalText(decimal value) => value.ToString("0.############", Invariant);
    private static PackagePriceCalculationRequestDto Custom(JourneyData d) => new() { ExtraHours = d.ExtraHours!.Value };

    private async Task<object> Input(JourneyState state, CustomerPhotographyRequirements requirements, Guid operation, CancellationToken ct)
    {
        object? studios = null, recommended = null, scheduling = null;
        if (state.Stage != "StudioMatching")
        {
            var studio = state.Selections["StudioMatching"];
            await CheckOption(studio, state, ct);
            studios = new { rankedStudios = new[] { new { studioId = studio.Data.StudioId, explanationSummary = "Selected by customer." } }, unmetPreferences = Array.Empty<string>() };
        }
        if (state.Stage is "Scheduling" or "Validation")
        {
            var package = state.Selections["PackageRecommendation"];
            await CheckOption(package, state, ct);
            var d = package.Data;
            var current = await packageRead(d.StudioId!.Value, d.PackageId!.Value) ?? throw Fail("package_unavailable");
            var quote = await priceRead(d.StudioId.Value, d.PackageId.Value, Custom(d)) ?? throw Fail("package_unavailable");
            if (quote.FinalPrice != Number(d.QuotedPrice!) || current.DurationHours != Number(d.DurationHours!)) throw Fail("price_changed");
            recommended = new { rankedPackages = new[] { new { studioId = d.StudioId, packageId = d.PackageId,
                explanationSummary = "Selected by customer.", customization = Custom(d), pricing = quote } }, unmetPreferences = Array.Empty<string>() };
            if (state.Stage == "Validation")
            {
                var selected = state.Selections["Scheduling"];
                var evidence = await Candidates(requirements, d, ct);
                var slot = evidence.Candidates.SingleOrDefault(c => c.Date.ToString("yyyy-MM-dd", Invariant) == selected.Data.Date &&
                    c.StartTime == TimeOnly.Parse(selected.Data.StartTime!, Invariant) && c.EndTime == TimeOnly.Parse(selected.Data.EndTime!, Invariant))
                    ?? throw Fail("slot_unavailable");
                scheduling = new { rankedSlots = new[] { new { studioId = d.StudioId, packageId = d.PackageId, date = slot.Date,
                    startTime = slot.StartTime, endTime = slot.EndTime, explanationSummary = "Selected by customer.", evidenceIds = slot.EvidenceIds } },
                    unmetPreferences = Array.Empty<string>(), backendEvidence = new[] { evidence with { Candidates = new[] { slot } } } };
            }
        }
        return new { operationId = operation, stage = state.Stage, requirements, studios, packages = recommended, scheduling };
    }

    private async Task<SchedulingCandidateResponseDto> Candidates(CustomerPhotographyRequirements r, JourneyData package, CancellationToken ct)
    {
        var result = await discover(package.StudioId!.Value, package.PackageId!.Value, new() {
            EarliestDate = r.EarliestDate, LatestDate = r.LatestDate, PreferredStartTime = r.PreferredStartTime,
            PreferredEndTime = r.PreferredEndTime, CoverageHours = r.CoverageHours, Customization = Custom(package) }, ct);
        return result.Response ?? throw Fail(result.ErrorCode ?? "slot_unavailable");
    }

    private async Task Complete(AiWorkflow w, JourneyState state, JsonElement output, CustomerPhotographyRequirements requirements, CancellationToken ct)
    {
        var seq = state.Sequence;
        var operation = state.Running!.Data.OperationId;
        AiWorkflowEvent Add(JourneyData data) => JourneyState.Append(w, state.Stage,
            data with { Revision = state.Revision, Sequence = ++seq, OperationId = operation }, Now);
        if (state.Stage == "Validation")
        {
            var evidence = JsonSerializer.Deserialize<FinalValidationResult>(output.GetRawText(), InternalPythonWorkflowClient.Wire) ?? throw new JsonException();
            using var expected = JsonDocument.Parse(CanonicalProposalService.Serialize(evidence));
            InternalPythonWorkflowClient.VerifyShape(output, expected.RootElement);
            var schedule = state.Selections["Scheduling"];
            var package = state.Selections["PackageRecommendation"];
            var selection = new RecommendationSelection { StudioId = schedule.Data.StudioId!.Value, PackageId = schedule.Data.PackageId!.Value,
                Date = DateOnly.Parse(schedule.Data.Date!, Invariant), StartTime = TimeOnly.Parse(schedule.Data.StartTime!, Invariant),
                EndTime = TimeOnly.Parse(schedule.Data.EndTime!, Invariant), Customization = Custom(package.Data) };
            if (!CanonicalProposalService.ValidEvidence(evidence, selection, clock.GetUtcNow()) ||
                evidence.Current!.Pricing!.FinalPrice != Number(package.Data.QuotedPrice!)) throw Fail("validation_failed");
            var prepared = await prepare(w, new() { WorkflowId = w.Id, ExpectedProposalVersion = w.ProposalVersion,
                Requirements = requirements, Selection = selection, Evidence = evidence, TimeZoneId = "Asia/Colombo", IsReservation = false }, ct);
            var proposal = prepared.Proposal ?? throw Fail(prepared.ErrorCode ?? "validation_failed");
            w.FinalProposalJson = CanonicalProposalService.Serialize(proposal);
            w.ProposalVersion = proposal.Version;
            w.SelectedStudioId = proposal.Selection.StudioId;
            w.SelectedPackageId = proposal.Selection.PackageId;
            w.ExpiresAt = proposal.ExpiresAtUtc.UtcDateTime;
            // Validation is a customer draft. AwaitingApproval is entered only by explicit submit.
            w.Status = AiWorkflowStatus.Validation;
            Add(new() { Kind = "validated", SourceEventId = schedule.Event.Id, QuotedPrice = DecimalText(proposal.Pricing.FinalPrice),
                ExpiresAt = proposal.ExpiresAtUtc.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", Invariant) });
            return;
        }
        var key = state.Stage switch { "StudioMatching" => "rankedStudios", "PackageRecommendation" => "rankedPackages", _ => "rankedSlots" };
        var options = output.GetProperty(key).EnumerateArray().ToArray();
        if (options.Length is < 1 or > 5) throw Fail("invalid_execution_response");
        var ids = new List<Guid>();
        var unique = new HashSet<string>();
        var rank = 0;
        SchedulingCandidateResponseDto? candidates = state.Stage == "Scheduling" ? await Candidates(requirements, state.Selections["PackageRecommendation"].Data, ct) : null;
        foreach (var option in options)
        {
            var studioId = option.GetProperty("studioId").GetGuid();
            if (studioId == Guid.Empty || await studioRead(studioId, ct) is null) throw Fail("unknown_studio_id");
            var reason = option.GetProperty("explanationSummary").GetString();
            if (string.IsNullOrWhiteSpace(reason) || reason.Length > 300 || reason.Any(char.IsControl)) throw new JsonException();
            JourneyData data;
            if (state.Stage == "StudioMatching")
            {
                if (!unique.Add(studioId.ToString())) throw new JsonException();
                data = new() { Kind = "studio-option", StudioId = studioId, Rank = ++rank, Reason = reason };
            }
            else
            {
                if (studioId != state.Selections["StudioMatching"].Data.StudioId) throw Fail("unknown_studio_id");
                var packageId = option.GetProperty("packageId").GetGuid();
                var p = await packageRead(studioId, packageId) ?? throw Fail("package_unavailable");
                if (state.Stage == "PackageRecommendation")
                {
                    if (!unique.Add(packageId.ToString())) throw new JsonException();
                    var extra = checked((int)decimal.Ceiling(Math.Max(0, requirements.CoverageHours - p.DurationHours)));
                    if (p.DurationHours <= 0 || p.DurationHours + extra > 24) throw Fail("invalid_package_input");
                    var quote = await priceRead(studioId, packageId, new() { ExtraHours = extra }) ?? throw Fail("package_unavailable");
                    if (quote.FinalPrice < 0 || quote.FinalPrice > 9999999999999999.99m || decimal.Round(quote.FinalPrice, 2) != quote.FinalPrice ||
                        decimal.Round(p.DurationHours, 12) != p.DurationHours) throw Fail("invalid_backend_response");
                    if (requirements.RequestedServices.Any(requested => !p.Services.Any(s => string.Equals(s.ServiceName.Trim(), requested.Trim(), StringComparison.OrdinalIgnoreCase))))
                        throw Fail("invalid_package_input");
                    if (quote.FinalPrice > requirements.MaximumBudget || quote.FinalPrice < (requirements.MinimumBudget ?? 0)) throw Fail("budget_failure");
                    if (option.GetProperty("customization").GetProperty("extraHours").GetInt32() != extra ||
                        decimal.Parse(option.GetProperty("pricing").GetProperty("finalPrice").ToString(), Invariant) != quote.FinalPrice) throw Fail("price_changed");
                    data = new() { Kind = "package-option", StudioId = studioId, PackageId = packageId, Rank = ++rank, Reason = reason,
                        SourceEventId = state.Selections["StudioMatching"].Event.Id, ExtraHours = extra,
                        QuotedPrice = DecimalText(quote.FinalPrice), DurationHours = DecimalText(p.DurationHours) };
                }
                else
                {
                    if (packageId != state.Selections["PackageRecommendation"].Data.PackageId) throw Fail("invalid_package_reference");
                    var date = DateOnly.Parse(option.GetProperty("date").GetString()!, Invariant);
                    var start = TimeOnly.Parse(option.GetProperty("startTime").GetString()!, Invariant);
                    var end = TimeOnly.Parse(option.GetProperty("endTime").GetString()!, Invariant);
                    if (!unique.Add($"{date}:{start.Ticks}:{end.Ticks}") || !candidates!.Candidates.Any(c => c.Date == date && c.StartTime == start && c.EndTime == end))
                        throw Fail("slot_unavailable");
                    data = new() { Kind = "schedule-option", StudioId = studioId, PackageId = packageId, Rank = ++rank, Reason = reason,
                        SourceEventId = state.Selections["PackageRecommendation"].Event.Id, Date = date.ToString("yyyy-MM-dd", Invariant),
                        StartTime = start.ToString("HH:mm:ss.fffffff", Invariant), EndTime = end.ToString("HH:mm:ss.fffffff", Invariant) };
                }
            }
            ids.Add(Add(data).Id);
        }
        Add(new() { Kind = "completed", OptionEventIds = ids.ToArray() });
    }

    private async Task<AiWorkflowResponse> Response(AiWorkflow w, CancellationToken ct)
    {
        var state = JourneyState.Read(w);
        var response = AiWorkflowService.ToResponse(w);
        if (state.Entries.Count == 0) return response;
        var options = new List<JourneyOption>();
        foreach (var entry in state.Options.Values.SelectMany(v => v))
        {
            var d = entry.Data;
            var studio = await studioRead(d.StudioId!.Value, ct);
            if (studio is null) continue;
            var p = d.PackageId is { } packageId ? await packageRead(studio.Id, packageId) : null;
            if (d.PackageId != null && p is null) continue;
            options.Add(new(entry.Event.Id, entry.Event.StepName, d.StudioId, d.PackageId, d.Rank!.Value,
                p?.Name ?? studio.StudioName, p?.CoverImageUrl ?? studio.CoverPhotoUrl, studio.Location, studio.PhotographyTypes,
                d.Reason, d.QuotedPrice is null ? null : Number(d.QuotedPrice), d.DurationHours is null ? null : Number(d.DurationHours), d.ExtraHours,
                p?.Services.Select(s => s.ServiceName).ToArray(), d.Date, d.StartTime, d.EndTime));
        }
        var submitted = w.Status is AiWorkflowStatus.AwaitingApproval or AiWorkflowStatus.Approved or AiWorkflowStatus.Rejected;
        return response with { Proposal = state.Validated is null ? null : response.Proposal,
            Journey = new(state.Revision, state.Stage, state.Running is not null && Now - state.Running.Event.CreatedAt < TimeSpan.FromMinutes(4),
                state.Validated is not null && w.ExpiresAt > Now && w.Status is not (AiWorkflowStatus.RevalidationRequired or AiWorkflowStatus.Failed), submitted,
                state.Running is not null && Now - state.Running.Event.CreatedAt >= TimeSpan.FromMinutes(4) ? "execution_timeout" : state.ErrorCode,
                state.Selections.GetValueOrDefault("StudioMatching")?.Event.Id,
                state.Selections.GetValueOrDefault("PackageRecommendation")?.Event.Id,
                state.Selections.GetValueOrDefault("Scheduling")?.Event.Id, options) };
    }
}
