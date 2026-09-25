using System.Data;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

/// <summary>Synchronous orchestration after submission commit; no DB transaction spans Python execution.</summary>
public sealed class AiWorkflowExecutionService
{
    private readonly Func<Guid, PythonExecutionRequest, CancellationToken, Task<PythonExecutionResult>> _run;
    private readonly Func<Guid, AiWorkflowStatus, AiWorkflowStatus, string, CancellationToken, Task<bool>> _transition;
    private readonly Func<ProposalPublicationRequest, CancellationToken, Task<ProposalPublicationResult>> _publish;
    private readonly Func<Guid, CancellationToken, Task<AiWorkflow>> _read;
    private readonly Func<bool> _transactionActive;

    public AiWorkflowExecutionService(ApplicationDbContext db, InternalPythonWorkflowClient python,
        AiWorkflowPublicationService publication, TimeProvider clock) : this(python.RunAsync,
        (id, expected, next, code, ct) => TransitionAsync(db, clock, id, expected, next, code, ct),
        publication.PublishAsync,
        (id, ct) => db.AiWorkflows.AsNoTracking().SingleAsync(w => w.Id == id, ct),
        () => db.Database.CurrentTransaction is not null || System.Transactions.Transaction.Current is not null) { }

    internal AiWorkflowExecutionService(
        Func<Guid, PythonExecutionRequest, CancellationToken, Task<PythonExecutionResult>> run,
        Func<Guid, AiWorkflowStatus, AiWorkflowStatus, string, CancellationToken, Task<bool>> transition,
        Func<ProposalPublicationRequest, CancellationToken, Task<ProposalPublicationResult>> publish,
        Func<Guid, CancellationToken, Task<AiWorkflow>> read, Func<bool> transactionActive)
    { _run = run; _transition = transition; _publish = publish; _read = read; _transactionActive = transactionActive; }

    public async Task<AiWorkflow> ExecuteAsync(AiWorkflow submitted, CancellationToken ct)
    {
        // Creation has already committed. Claim this submission once; never replay a completed result.
        if (_transactionActive()) throw new InvalidOperationException("Execution requires a committed submission.");
        var input = new PythonExecutionRequest(Guid.NewGuid(),
            CanonicalProposalService.Read<CustomerPhotographyRequirements>(submitted.NormalizedRequirementsJson));
        var expected = AiWorkflowStatus.StudioMatching;
        try
        {
            if (!await _transition(submitted.Id, AiWorkflowStatus.Submitted, expected, "execution_started", ct))
                return await _read(submitted.Id, ct);
            if (_transactionActive()) throw new InvalidOperationException("Execution requires no active transaction.");
            var outcome = await _run(submitted.Id, input, ct);
            if (outcome.Completion is { } completion)
            {
                InternalPythonWorkflowClient.Validate(completion, submitted.Id, input);
                if (completion.Status == "AwaitingApproval")
                {
                    if (!await _transition(submitted.Id, expected, AiWorkflowStatus.Validation, "execution_validated", ct))
                        return await _read(submitted.Id, ct);
                    expected = AiWorkflowStatus.Validation;
                    // Version zero is a server-owned initial-publication precondition, not Python input.
                    var result = await _publish(new() { WorkflowId = submitted.Id, ExpectedProposalVersion = 0,
                        Requirements = input.Requirements, Selection = completion.Evidence!.Current!.Selection,
                        Evidence = completion.Evidence, TimeZoneId = "Asia/Colombo", IsReservation = false }, ct);
                    if (result.Proposal is null)
                        await _transition(submitted.Id, expected,
                            result.Classification == FinalValidationClassification.RevalidationRequired
                                ? AiWorkflowStatus.RevalidationRequired : AiWorkflowStatus.Failed, "publication_failed", ct);
                }
                else
                    await _transition(submitted.Id, expected, Enum.Parse<AiWorkflowStatus>(completion.Status), completion.ErrorCode!, ct);
            }
            else
                await _transition(submitted.Id, expected, AiWorkflowStatus.Failed, SafeCode(outcome.ErrorCode), ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // Bounded best-effort cleanup after request cancellation; never fire-and-forget.
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await _transition(submitted.Id, expected, AiWorkflowStatus.Failed, "execution_cancelled", cleanup.Token);
            throw;
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or HttpRequestException or TimeoutException
            or ArgumentException or InvalidOperationException or OperationCanceledException)
        {
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await _transition(submitted.Id, expected, AiWorkflowStatus.Failed, "invalid_execution_response", cleanup.Token);
        }
        return await _read(submitted.Id, ct);
    }

    private static string SafeCode(string? code) => code is "execution_timeout" or "execution_unavailable" or
        "execution_unauthorized" or "invalid_execution_response" or "execution_failed" or "execution_cancelled" or
        "execution_started" or "execution_validated" or "publication_failed" or "revalidation_required" or "needs_input"
        ? code : "execution_failed";

    // Status describes the outcome; CurrentStep is a durable stage constrained by the Phase 2 schema.
    internal static string ExecutionStep(AiWorkflowStatus status) => status switch
    {
        AiWorkflowStatus.StudioMatching => "StudioMatching",
        AiWorkflowStatus.Validation or AiWorkflowStatus.RevalidationRequired => "Validation",
        AiWorkflowStatus.Failed or AiWorkflowStatus.NeedsInput => "Completed",
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, "Not an execution transition.")
    };

    private static async Task<bool> TransitionAsync(ApplicationDbContext db, TimeProvider clock, Guid id,
        AiWorkflowStatus expected, AiWorkflowStatus next, string code, CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);
        var rows = await db.AiWorkflows.FromSqlInterpolated(
            $"SELECT *, xmin FROM public.\"AiWorkflows\" WHERE \"Id\" = {id} FOR UPDATE").ToListAsync(ct);
        var workflow = rows.SingleOrDefault();
        if (workflow is null) return false;
        // A tracked submission may predate this lock; reload the locked row before checking the precondition.
        await db.Entry(workflow).ReloadAsync(ct);
        if (workflow.Status != expected || workflow.ProposalVersion != 0 || workflow.FinalProposalJson is not null) return false;
        workflow.Status = next;
        workflow.CurrentStep = ExecutionStep(next);
        workflow.UpdatedAt = clock.GetUtcNow().UtcDateTime;
        db.AiWorkflowEvents.Add(new AiWorkflowEvent { WorkflowId = id, EventType = "WorkflowExecutionStateChanged",
            StepName = workflow.CurrentStep, Summary = "Internal workflow execution state updated.",
            Success = next is AiWorkflowStatus.StudioMatching or AiWorkflowStatus.Validation,
            DetailsJson = CanonicalProposalService.Serialize(new { errorCode = SafeCode(code) }), CreatedAt = workflow.UpdatedAt });
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return true;
    }
}
