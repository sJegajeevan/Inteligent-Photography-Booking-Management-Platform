using System.Net;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

internal static class PythonExecutionChecks
{
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => send(request, ct);
    }
    private sealed class Clock(DateTimeOffset now) : TimeProvider
    { public override DateTimeOffset GetUtcNow() => now; }
    private sealed class StreamingBody(byte[] bytes) : MemoryStream(bytes)
    { public override bool CanSeek => false; }
    private static HttpResponseMessage Response(string body, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    public static async Task<int> RunAsync()
    {
        var count = 0;
        void Check(bool ok, string name) { if (!ok) throw new Exception("FAILED Python execution: " + name); count++; }
        using var schemaStream = typeof(PythonExecutionChecks).Assembly.GetManifestResourceStream("Phase2Schema.sql")!;
        var schema = await new StreamReader(schemaStream).ReadToEndAsync();
        var stepConstraint = schema.Split('\n').Single(line => line.Contains("CK_AiWorkflows_Step"));
        var durableSteps = System.Text.RegularExpressions.Regex.Matches(stepConstraint, "'([^']+)'")
            .Select(match => match.Groups[1].Value).ToHashSet();
        Check(!durableSteps.Contains("Failed") && !durableSteps.Contains("NeedsInput"), "outcomes are not Phase 2 steps");
        foreach (var status in new[] { AiWorkflowStatus.StudioMatching, AiWorkflowStatus.Validation,
            AiWorkflowStatus.RevalidationRequired, AiWorkflowStatus.Failed, AiWorkflowStatus.NeedsInput })
            Check(durableSteps.Contains(AiWorkflowExecutionService.ExecutionStep(status)), "Phase 2 accepts execution step " + status);
        Check(AiWorkflowExecutionService.ExecutionStep(AiWorkflowStatus.Failed) == "Completed" &&
            AiWorkflowExecutionService.ExecutionStep(AiWorkflowStatus.NeedsInput) == "Completed", "terminal execution stage");
        using var fixture = typeof(PythonExecutionChecks).Assembly.GetManifestResourceStream("Phase1Checks.Fixtures.python-completion.json")!;
        var json = await new StreamReader(fixture).ReadToEndAsync();
        var completion = JsonSerializer.Deserialize<PythonExecutionCompletion>(json, InternalPythonWorkflowClient.Wire)!;
        var input = new PythonExecutionRequest(completion.ExecutionId, completion.Requirements);
        const string token = "offline-internal-service-test-token-32-characters";
        var options = new PythonWorkflowOptions("http://python.internal:8000", token, 1);
        var calls = 0;
        string sentBody = "";
        using var http = new HttpClient(new Handler(async (request, ct) =>
        {
            calls++;
            Check(request.Method == HttpMethod.Post && request.RequestUri!.ToString() ==
                $"http://python.internal:8000/internal/ai-workflows/{completion.WorkflowId}/run", "fixed configured endpoint");
            Check(request.Headers.GetValues("X-Internal-Token").Single() == token, "service token internal header");
            sentBody = await request.Content!.ReadAsStringAsync(ct);
            return Response(json);
        }));
        var client = new InternalPythonWorkflowClient(http, options);
        var response = await client.RunAsync(completion.WorkflowId, input, default);
        Check(response.ErrorCode is null && response.Completion?.Status == "AwaitingApproval", "actual Python wire fixture accepted");
        Check(!sentBody.Contains(token) && !sentBody.Contains("customerId") && !sentBody.Contains("proposalVersion") &&
            !sentBody.Contains("reviewer") && !sentBody.Contains("backendUrl"), "narrow request has no authority or secrets");
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try { await client.RunAsync(completion.WorkflowId, input, cancelled.Token); Check(false, "cancellation"); }
            catch (OperationCanceledException) { Check(calls == 1, "caller cancellation prevents dispatch"); }
        }
        async Task<PythonExecutionResult> Send(string body, HttpStatusCode status = HttpStatusCode.OK)
        {
            using var fake = new HttpClient(new Handler((_, _) => Task.FromResult(Response(body, status))));
            return await new InternalPythonWorkflowClient(fake, options).RunAsync(completion.WorkflowId, input, default);
        }
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden, HttpStatusCode.ServiceUnavailable,
            HttpStatusCode.Redirect, HttpStatusCode.InternalServerError })
        {
            var result = await Send("PRIVATE provider secret", status);
            Check(result.Completion is null && result.ErrorCode == (status is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden
                ? "execution_unauthorized" : "execution_unavailable"), "safe HTTP failure " + status);
        }
        foreach (var body in new[] { "PRIVATE", "null", "{}", new string('x', InternalPythonWorkflowClient.ResponseLimit + 1),
            json.Replace("\"status\":", "\"status\":\"Approved\",\"status\":") })
            Check((await Send(body)).ErrorCode == "invalid_execution_response", "malformed/bounded response");
        foreach (var mutate in new Action<JsonNode>[] {
            n => n["customerId"] = 7, n => n["proposalVersion"] = 99, n => n["reviewer"] = 1,
            n => n["workflowId"] = Guid.NewGuid(), n => n["executionId"] = Guid.NewGuid(),
            n => n["requirements"]!["maximumBudget"] = 1, n => n["requirements"]!["timeZoneId"] = "UTC",
            n => n["evidence"]!["isReservation"] = true, n => n["evidence"]!["classification"] = 0,
            n => n["evidence"]!["current"]!["selection"]!["customerId"] = 7,
            n => n["evidence"] = null, n => n["schedulingEvidence"] = null,
            n => n["schedulingEvidence"]!["candidates"]![0]!["date"] = "2027-12-03",
            n => n["status"] = "Approved", n => n.AsObject().Remove("errorCode") })
        {
            var node = JsonNode.Parse(json)!; mutate(node);
            Check((await Send(node.ToJsonString())).ErrorCode == "invalid_execution_response", "untrusted authority/evidence rejected");
        }
        foreach (var failure in new[] { "timeout", "unavailable" })
        {
            using var fake = new HttpClient(new Handler(async (_, ct) =>
            {
                if (failure == "unavailable") throw new HttpRequestException("PRIVATE");
                await Task.Delay(TimeSpan.FromSeconds(10), ct);
                throw new Exception("Timeout did not cancel");
            }));
            var result = await new InternalPythonWorkflowClient(fake, options).RunAsync(completion.WorkflowId, input, default);
            Check(result.ErrorCode == "execution_" + failure && result.Completion is null, "safe transport " + failure);
        }
        foreach (var invalid in new[] { options with { BaseUrl = "http://python.internal/arbitrary" },
            options with { BaseUrl = "http://user:password@python.internal" }, options with { Token = "" },
            options with { TimeoutSeconds = 181 }, options with { BaseUrl = "file:///private" } })
            Check((await new InternalPythonWorkflowClient(http, invalid).RunAsync(completion.WorkflowId, input, default)).ErrorCode ==
                "execution_unavailable", "invalid environment configuration fails closed");
        Check(calls == 1, "invalid configuration never dispatched");
        using (var streamingHttp = new HttpClient(new Handler((_, _) =>
        {
            var message = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(
                new StreamingBody(new byte[InternalPythonWorkflowClient.ResponseLimit + 1])) };
            message.Content.Headers.ContentType = new("application/json");
            return Task.FromResult(message);
        })))
            Check((await new InternalPythonWorkflowClient(streamingHttp, options).RunAsync(completion.WorkflowId, input, default)).ErrorCode ==
                "invalid_execution_response", "stream capped without Content-Length");
        using (var cancelled = new CancellationTokenSource())
        using (var slowHttp = new HttpClient(new Handler(async (_, ct) =>
        {
            cancelled.Cancel();
            await Task.Delay(10000, ct);
            return Response(json);
        })))
        {
            try { await new InternalPythonWorkflowClient(slowHttp, options).RunAsync(completion.WorkflowId, input, cancelled.Token);
                Check(false, "active cancellation"); }
            catch (OperationCanceledException) { Check(true, "active HTTP cancellation propagates"); }
        }

        // Real orchestration + canonical fresh validation; only persistence/HTTP boundaries are replaced.
        var clock = new Clock(completion.Evidence!.CheckedAtUtc);
        var current = completion.Evidence.Current!;
        var price = current.Pricing!.FinalPrice;
        var freshReads = 0;
        var validation = new FinalRecommendationValidationService(clock, (selection, today, ct) =>
        {
            freshReads++;
            return Task.FromResult<(PhotographyPackageResponseDto?, RecommendationCheck)>((
                new PhotographyPackageResponseDto { Id = selection.PackageId, StudioId = selection.StudioId,
                    Status = "Active", DurationHours = current.PackageDurationHours,
                    Services = current.IncludedServices.Select(s => new PhotographyPackageServiceDto { Id = s.Id, ServiceName = s.ServiceName }).ToArray() },
                new(new(ValidationOutcome.Pass, [], clock.GetUtcNow()),
                    new PackagePriceCalculationResponseDto { PackageId = selection.PackageId, FinalPrice = price,
                        ExtraHours = selection.Customization.ExtraHours })));
        });
        var canonical = new CanonicalProposalService(validation, clock);
        AiWorkflow? row = null;
        var committed = false; var transactionActive = false; var runs = 0; var publishes = 0;
        string outcome = "AwaitingApproval";
        CancellationTokenSource? callerCancellation = null;
        var execution = new AiWorkflowExecutionService(async (id, request, ct) =>
        {
            runs++;
            Check(committed && row?.Status == AiWorkflowStatus.StudioMatching, "submission committed before Python");
            Check(!transactionActive, "no transaction held during Python");
            await Task.Yield();
            if (outcome == "cancel") { callerCancellation!.Cancel(); ct.ThrowIfCancellationRequested(); }
            if (outcome == "invalid_operation") throw new InvalidOperationException("Offline execution failure");
            if (outcome == "invalid_argument") throw new ArgumentException("Offline invalid completion");
            if (outcome == "internal_cancel") throw new OperationCanceledException();
            if (outcome is "execution_timeout" or "execution_unavailable" or "invalid_execution_response") return new(null, outcome);
            return new(completion with { WorkflowId = id, ExecutionId = request.ExecutionId, Status = outcome,
                Evidence = outcome == "AwaitingApproval" ? completion.Evidence : null,
                SchedulingEvidence = outcome == "AwaitingApproval" ? completion.SchedulingEvidence : null,
                ErrorCode = outcome == "AwaitingApproval" ? null : "execution_failed" }, null);
        }, (id, expected, next, code, ct) =>
        {
            Check(!transactionActive, "transition opens its own short transaction");
            transactionActive = true;
            var matches = row!.Status == expected && row.ProposalVersion == 0;
            if (matches)
            {
                row.Status = next;
                row.CurrentStep = AiWorkflowExecutionService.ExecutionStep(next);
                Check(durableSteps.Contains(row.CurrentStep), "persisted transition obeys SQL step constraint");
            }
            transactionActive = false;
            return Task.FromResult(matches);
        }, async (request, ct) =>
        {
            publishes++;
            Check(request.ExpectedProposalVersion == 0 && CanonicalProposalService.Same(request.Requirements, input.Requirements),
                "server owns version and stored requirements");
            var result = await canonical.PrepareAsync(row!, request, ct);
            AiWorkflowPublicationService.ApplyResult(row!, result, clock.GetUtcNow().UtcDateTime);
            return result;
        }, (_, _) => Task.FromResult(row!), () => transactionActive);
        var service = new AiWorkflowService(clock, (_, _) => Task.FromResult<User?>(new User { Id = 73, Role = "Customer" }),
            (_, _, _) => Task.FromResult<AiWorkflow?>(row), (_, _, _) => Task.FromResult(new List<AiWorkflow>()),
            (workflow, _) => { row = workflow; committed = true; return Task.CompletedTask; },
            (_, _, _, _, _, _) => throw new Exception("No approval in execution"), execution.ExecuteAsync);
        var actor = new ClaimsPrincipal(new ClaimsIdentity([new(ClaimTypes.NameIdentifier, "73"), new(ClaimTypes.Role, "Customer")], "offline"));
        var created = await service.CreateAsync(new() { Requirements = input.Requirements }, actor, default);
        Check(created.Status == "AwaitingApproval" && created.CurrentStep == "HumanApproval" && created.ProposalVersion == 1,
            "success publishes canonical proposal");
        Check(freshReads == 1 && publishes == 1 && runs == 1, "fresh backend validation before publication");
        Check(row!.CustomerId == 73 && row.Approvals.Count == 0 && created.Proposal!.RequiresHumanApproval && !created.Proposal.IsReservation,
            "execution cannot approve or reserve");
        Check(!CanonicalProposalService.Serialize(created).Contains(token) && !CanonicalProposalService.Serialize(created).Contains("NormalizedRequirementsJson"),
            "sanitized customer DTO");
        await execution.ExecuteAsync(row!, default);
        Check(runs == 1 && publishes == 1, "duplicate execution does not publish twice");
        foreach (var status in new[] { "Failed", "RevalidationRequired", "NeedsInput", "execution_timeout", "execution_unavailable", "invalid_execution_response",
            "invalid_operation", "invalid_argument", "internal_cancel" })
        {
            outcome = status; committed = false;
            var failed = await service.CreateAsync(new() { Requirements = input.Requirements }, actor, default);
            Check(failed.Status == (status.StartsWith("execution_") || status.StartsWith("invalid_") || status == "internal_cancel" ? "Failed" : status) &&
                failed.Proposal is null && failed.ProposalVersion == 0, "durable safe outcome " + status);
            Check(failed.CurrentStep == (status == "RevalidationRequired" ? "Validation" : "Completed"),
                "failure exits Processing with a durable stage " + status);
            Check(publishes == 1, "failure never publishes " + status);
        }
        outcome = "AwaitingApproval"; price++;
        var revalidated = await service.CreateAsync(new() { Requirements = input.Requirements }, actor, default);
        Check(revalidated.Status == "RevalidationRequired" && revalidated.Proposal is null && revalidated.ProposalVersion == 0,
            "fresh price change blocks stale publication");
        Check(freshReads == 2, "publication always rereads authoritative data");
        outcome = "cancel";
        using (callerCancellation = new CancellationTokenSource())
        {
            try { await service.CreateAsync(new() { Requirements = input.Requirements }, actor, callerCancellation.Token);
                Check(false, "orchestration cancellation"); }
            catch (OperationCanceledException) { Check(row!.Status == AiWorkflowStatus.Failed && row.FinalProposalJson is null,
                "cancelled execution persists safe failure before propagation"); }
        }
        var runsBeforeFailedSave = runs;
        var failedSave = new AiWorkflowService(clock, (_, _) => Task.FromResult<User?>(new User { Id = 73, Role = "Customer" }),
            (_, _, _) => Task.FromResult<AiWorkflow?>(row), (_, _, _) => Task.FromResult(new List<AiWorkflow>()),
            (_, _) => throw new InvalidOperationException("Offline commit failure"),
            (_, _, _, _, _, _) => throw new Exception("No approval"), execution.ExecuteAsync);
        try { await failedSave.CreateAsync(new() { Requirements = input.Requirements }, actor, default); Check(false, "commit failure"); }
        catch (InvalidOperationException) { Check(runs == runsBeforeFailedSave, "failed commit never dispatches Python"); }
        transactionActive = true;
        var before = runs;
        try { await execution.ExecuteAsync(row!, default); Check(false, "active transaction blocked"); }
        catch (InvalidOperationException) { Check(runs == before, "active transaction prevents Python call"); }
        return count;
    }
}
