using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public sealed class AiWorkflowApiFailure(string code) : Exception(code)
{
    public string Code { get; } = code;
}

/// <summary>
/// Customer persistence, post-commit execution, and role-scoped queries.
/// No booking dependency.
/// </summary>
public sealed class AiWorkflowService
{
    private readonly TimeProvider _clock;

    private readonly Func<int, CancellationToken, Task<User?>> _user;

    private readonly Func<
        User,
        Guid,
        CancellationToken,
        Task<AiWorkflow?>
    > _get;

    private readonly Func<
        User,
        AiWorkflowListRequest,
        CancellationToken,
        Task<List<AiWorkflow>>
    > _list;

    private readonly Func<
        AiWorkflow,
        CancellationToken,
        Task
    > _save;

    private readonly Func<
        AiWorkflow,
        CancellationToken,
        Task<AiWorkflow>
    > _execute;

    private readonly Func<
        Guid,
        int,
        AiApprovalDecision,
        string?,
        ClaimsPrincipal,
        CancellationToken,
        Task<AiWorkflowDecisionResult>
    > _decide;

    public AiWorkflowService(
        ApplicationDbContext db,
        AiWorkflowApprovalService approvals,
        TimeProvider clock,
        AiWorkflowExecutionService execution
    ) : this(
        clock,

        (id, ct) =>
            db.Users
                .AsNoTracking()
                .SingleOrDefaultAsync(
                    u => u.Id == id,
                    ct
                ),

        (actor, id, ct) =>
            ReadProjection(
                Scope(
                    db.AiWorkflows.AsNoTracking(),
                    actor
                )
                .Where(w => w.Id == id)
            )
            .SingleOrDefaultAsync(ct),

        (actor, request, ct) =>
            ReadProjection(
                PageQuery(
                    Scope(
                        db.AiWorkflows.AsNoTracking(),
                        actor
                    ),
                    request
                )
            )
            .ToListAsync(ct),

        async (workflow, ct) =>
        {
            db.AiWorkflows.Add(workflow);

            await db.SaveChangesAsync(ct);
        },

        approvals.RecordDecisionAsync,

        execution.ExecuteAsync
    )
    {
    }

    // Offline checks replace only database boundaries;
    // role checks, normalization and DTOs remain real.
    internal AiWorkflowService(
        TimeProvider clock,
        Func<
            int,
            CancellationToken,
            Task<User?>
        > user,
        Func<
            User,
            Guid,
            CancellationToken,
            Task<AiWorkflow?>
        > get,
        Func<
            User,
            AiWorkflowListRequest,
            CancellationToken,
            Task<List<AiWorkflow>>
        > list,
        Func<
            AiWorkflow,
            CancellationToken,
            Task
        > save,
        Func<
            Guid,
            int,
            AiApprovalDecision,
            string?,
            ClaimsPrincipal,
            CancellationToken,
            Task<AiWorkflowDecisionResult>
        > decide,
        Func<
            AiWorkflow,
            CancellationToken,
            Task<AiWorkflow>
        >? execute = null
    )
    {
        _clock = clock;
        _user = user;
        _get = get;
        _list = list;
        _save = save;
        _decide = decide;

        _execute =
            execute ??
            ((workflow, _) =>
                Task.FromResult(workflow));
    }

    internal static IQueryable<AiWorkflow> Scope(
        IQueryable<AiWorkflow> query,
        User actor
    ) =>
        actor.Role switch
        {
            "Customer" =>
                query.Where(
                    w => w.CustomerId == actor.Id
                ),

            "Studio" =>
                query.Where(
                    w =>
                        w.SelectedStudio != null &&
                        w.SelectedStudio.UserId == actor.Id &&
                        (!w.Events.Any(e => e.EventType == "JourneyV1") ||
                         w.Status == AiWorkflowStatus.AwaitingApproval || w.Status == AiWorkflowStatus.Approved || w.Status == AiWorkflowStatus.Rejected)
                ),

            "Admin" =>
                query,

            _ =>
                query.Where(w => false)
        };

    internal static IQueryable<AiWorkflow> PageQuery(
        IQueryable<AiWorkflow> query,
        AiWorkflowListRequest request
    )
    {
        Validate(request);

        if (request.Status is not null)
        {
            var status =
                Enum.Parse<AiWorkflowStatus>(
                    request.Status
                );

            query =
                query.Where(
                    w => w.Status == status
                );
        }

        return query
            .OrderByDescending(w => w.CreatedAt)
            .ThenBy(w => w.Id)
            .Skip(
                (request.Page - 1) *
                request.PageSize
            )
            .Take(
                request.PageSize + 1
            );
    }

    private static IQueryable<AiWorkflow> ReadProjection(
        IQueryable<AiWorkflow> query
    ) =>
        query.Select(
            w => new AiWorkflow
            {
                Id = w.Id,

                Status = w.Status,

                CurrentStep =
                    w.CurrentStep,

                ProposalVersion =
                    w.ProposalVersion,

                SelectedStudioId =
                    w.SelectedStudioId,

                SelectedPackageId =
                    w.SelectedPackageId,

                FinalProposalJson =
                    w.FinalProposalJson,

                CreatedAt =
                    w.CreatedAt,

                UpdatedAt =
                    w.UpdatedAt,

                ExpiresAt =
                    w.ExpiresAt,
                Events = w.Events.Where(e => e.EventType == "JourneyV1" || e.EventType == "WorkflowExecutionStateChanged" && !e.Success).ToList()
            }
        );

    private async Task<User> ActorAsync(
        ClaimsPrincipal principal,
        CancellationToken ct
    )
    {
        ct.ThrowIfCancellationRequested();

        if (
            principal.Identity?.IsAuthenticated
            != true
        )
        {
            throw new AiWorkflowApiFailure(
                "unauthenticated"
            );
        }

        if (
            !int.TryParse(
                principal.FindFirstValue(
                    ClaimTypes.NameIdentifier
                ),
                out var id
            )
            ||
            id <= 0
        )
        {
            throw new AiWorkflowApiFailure(
                "not_found"
            );
        }

        var actor =
            await _user(
                id,
                ct
            );

        if (
            actor is null
            ||
            actor.Role is not (
                "Customer"
                or "Studio"
                or "Admin"
            )
            ||
            !principal.IsInRole(actor.Role)
        )
        {
            throw new AiWorkflowApiFailure(
                "not_found"
            );
        }

        return actor;
    }

    private static void Validate(
        object? value
    )
    {
        if (
            value is null
            ||
            !Validator.TryValidateObject(
                value,
                new ValidationContext(value),
                [],
                true
            )
        )
        {
            throw new AiWorkflowApiFailure(
                "invalid_request"
            );
        }
    }

    internal static CustomerPhotographyRequirements Normalize(
        CustomerPhotographyRequirements input
    )
    {
        Validate(input);

        // Persist only the bounded requirements contract.
        // Notes and transient GPS are not workflow state.
        return new()
        {
            PhotographyType =
                input.PhotographyType.Trim(),

            Location =
                input.Location.Trim(),

            MinimumBudget =
                input.MinimumBudget,

            MaximumBudget =
                input.MaximumBudget,

            EarliestDate =
                input.EarliestDate,

            LatestDate =
                input.LatestDate,

            PreferredStartTime =
                input.PreferredStartTime,

            PreferredEndTime =
                input.PreferredEndTime,

            CoverageHours =
                input.CoverageHours,

            RequestedServices =
                input.RequestedServices
                    .Select(s => s.Trim())
                    .Distinct(
                        StringComparer.OrdinalIgnoreCase
                    )
                    .ToArray()
        };
    }

    public async Task<AiWorkflowResponse> CreateAsync(
        CreateAiWorkflowRequest request,
        ClaimsPrincipal principal,
        CancellationToken ct
    )
    {
        var actor =
            await ActorAsync(
                principal,
                ct
            );

        if (actor.Role != "Customer")
        {
            throw new AiWorkflowApiFailure(
                "not_found"
            );
        }

        Validate(request);

        var requirements =
            Normalize(
                request.Requirements
            );

        var now =
            _clock
                .GetUtcNow()
                .UtcDateTime;

        var workflow =
            new AiWorkflow
            {
                CustomerId =
                    actor.Id,

                Status =
                    AiWorkflowStatus.Submitted,

                CurrentStep =
                    "Submitted",

                NormalizedRequirementsJson =
                    CanonicalProposalService.Serialize(
                        requirements
                    ),

                CreatedAt =
                    now,

                UpdatedAt =
                    now,

                // Submission lifetime is separate
                // from publication's five-minute
                // proposal lifetime.
                ExpiresAt =
                    now.AddHours(24)
            };

        workflow.Events.Add(
            new AiWorkflowEvent
            {
                WorkflowId =
                    workflow.Id,

                EventType =
                    "WorkflowSubmitted",

                StepName =
                    "Submitted",

                Summary =
                    "Customer workflow submitted.",

                Success =
                    true,

                CreatedAt =
                    now
            }
        );

        // EF SaveChanges commits workflow + event
        // before any Python dispatch.
        await _save(
            workflow,
            ct
        );

        return ToResponse(
            await _execute(
                workflow,
                ct
            )
        );
    }

    public async Task<AiWorkflowResponse> GetAsync(
        Guid id,
        ClaimsPrincipal principal,
        CancellationToken ct
    )
    {
        var actor =
            await ActorAsync(
                principal,
                ct
            );

        if (id == Guid.Empty)
        {
            throw new AiWorkflowApiFailure(
                "invalid_request"
            );
        }

        var workflow =
            await _get(
                actor,
                id,
                ct
            )
            ??
            throw new AiWorkflowApiFailure(
                "not_found"
            );

        return ToResponse(
            workflow
        );
    }

    public async Task<AiWorkflowPage> ListAsync(
        AiWorkflowListRequest request,
        ClaimsPrincipal principal,
        CancellationToken ct
    )
    {
        var actor =
            await ActorAsync(
                principal,
                ct
            );

        Validate(request);

        var workflows =
            await _list(
                actor,
                request,
                ct
            );

        return new(
            workflows
                .Take(request.PageSize)
                .Select(ToResponse)
                .ToArray(),

            request.Page,

            request.PageSize,

            workflows.Count >
                request.PageSize
        );
    }

    public async Task<AiWorkflowDecisionResult> DecideAsync(
        Guid id,
        int version,
        AiApprovalDecision decision,
        string? reason,
        ClaimsPrincipal principal,
        CancellationToken ct
    )
    {
        var actor =
            await ActorAsync(
                principal,
                ct
            );

        if (
            actor.Role is not (
                "Studio"
                or "Admin"
            )
        )
        {
            throw new AiWorkflowApiFailure(
                "not_found"
            );
        }

        if (
            id == Guid.Empty
            ||
            version <= 0
            ||
            decision is not (
                AiApprovalDecision.Approved
                or AiApprovalDecision.Rejected
            )
            ||
            (
                decision ==
                    AiApprovalDecision.Rejected
                &&
                (
                    string.IsNullOrWhiteSpace(
                        reason
                    )
                    ||
                    reason.Length > 1000
                )
            )
        )
        {
            throw new AiWorkflowApiFailure(
                "invalid_request"
            );
        }

        // The approval service repeats DB
        // role/ownership verification under
        // its existing locking boundary.
        return await _decide(
            id,
            version,
            decision,
            reason,
            principal,
            ct
        );
    }

    internal static AiWorkflowResponse ToResponse(
        AiWorkflow workflow
    )
    {
        FinalRecommendationProposal? proposal =
            null;

        if (
            workflow.FinalProposalJson
            is not null
        )
        {
            proposal =
                CanonicalProposalService
                    .Read<FinalRecommendationProposal>(
                        workflow.FinalProposalJson
                    );

            /*
             * PostgreSQL timestamps have microsecond precision,
             * while .NET DateTime can retain finer tick precision.
             *
             * Example:
             * JSON/Proposal:
             * 2026-09-26T08:00:28.9890725Z
             *
             * PostgreSQL:
             * 2026-09-26T08:00:28.9890720Z
             *
             * Therefore exact DateTime equality is too strict.
             */
            var expiryDifference =
                (
                    proposal
                        .ExpiresAtUtc
                        .UtcDateTime
                    -
                    workflow.ExpiresAt
                )
                .Duration();

            var expiryMatches =
                expiryDifference <
                TimeSpan.FromMicroseconds(1);

            if (
                proposal.Version !=
                    workflow.ProposalVersion
                ||
                proposal.Selection.StudioId !=
                    workflow.SelectedStudioId
                ||
                proposal.Selection.PackageId !=
                    workflow.SelectedPackageId
                ||
                !expiryMatches
            )
            {
                throw new InvalidOperationException(
                    "Invalid stored proposal."
                );
            }
        }

        return new(
            workflow.Id,
            workflow.Status.ToString(),
            workflow.CurrentStep,
            workflow.ProposalVersion,
            workflow.SelectedStudioId,
            workflow.SelectedPackageId,
            workflow.Events.Any(e => e.EventType == "JourneyV1") && JourneyState.Read(workflow).Validated is null ? null : proposal,
            workflow.CreatedAt,
            workflow.UpdatedAt,
            workflow.ExpiresAt
        ) { Failure = ReadFailure(workflow) };
    }

    private static AiWorkflowFailure? ReadFailure(AiWorkflow workflow)
    {
        if (workflow.Status is not (AiWorkflowStatus.Failed or AiWorkflowStatus.NeedsInput or AiWorkflowStatus.RevalidationRequired)) return null;
        var item = workflow.Events.Where(e => e.EventType == "WorkflowExecutionStateChanged" && !e.Success)
            .OrderByDescending(e => e.CreatedAt).FirstOrDefault();
        if (item?.DetailsJson is null) return null;
        try {
            using var json = System.Text.Json.JsonDocument.Parse(item.DetailsJson);
            var code = json.RootElement.GetProperty("errorCode").GetString();
            if (!AiExecutionFailure.ValidCode(code)) return null;
            return new(AiExecutionFailure.ValidStage(item.StepName) ? item.StepName : "Execution", code!, AiExecutionFailure.Message(code!));
        } catch (Exception error) when (error is System.Text.Json.JsonException or KeyNotFoundException or InvalidOperationException) { return null; }
    }
}
