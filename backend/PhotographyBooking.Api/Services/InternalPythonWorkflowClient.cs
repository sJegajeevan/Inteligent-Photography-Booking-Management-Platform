using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using PhotographyBooking.Api.Contracts.AgenticAi;

namespace PhotographyBooking.Api.Services;

public sealed record PythonWorkflowOptions(string? BaseUrl, string? Token, int TimeoutSeconds = 150)
{
    // Secrets come only from process environment, never appsettings or customer input.
    public static PythonWorkflowOptions FromEnvironment() => new(
        Environment.GetEnvironmentVariable("AI_WORKFLOW_PYTHON_BASE_URL"),
        Environment.GetEnvironmentVariable("INTERNAL_WORKFLOW_TOKEN"),
        int.TryParse(Environment.GetEnvironmentVariable("AI_WORKFLOW_TIMEOUT_SECONDS"), out var seconds) ? seconds : 150);

    internal bool Valid(out Uri? origin)
    {
        origin = null;
        return Uri.TryCreate(BaseUrl, UriKind.Absolute, out origin) && origin.Scheme is "http" or "https" &&
            origin.AbsolutePath == "/" && origin.UserInfo == "" && origin.Query == "" && origin.Fragment == "" &&
            Token is { Length: >= 32 and <= 512 } && Token.All(c => c is >= '!' and <= '~') &&
            TimeoutSeconds is >= 1 and <= 180;
    }
}

public sealed class InternalPythonWorkflowClient(HttpClient http, PythonWorkflowOptions options)
{
    public const int ResponseLimit = 65536;
    internal static readonly JsonSerializerOptions Wire = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
        PropertyNameCaseInsensitive = false, MaxDepth = 32
    };

    public async Task<PythonExecutionResult> RunAsync(Guid workflowId, PythonExecutionRequest input, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if (!options.Valid(out var origin)) return new(null, "execution_unavailable");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(options.TimeoutSeconds));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(origin!, $"internal/ai-workflows/{workflowId:D}/run"));
            request.Headers.Add("X-Internal-Token", options.Token);
            request.Content = new StringContent(CanonicalProposalService.Serialize(input), Encoding.UTF8, "application/json");
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                return new(null, "execution_unauthorized");
            if (response.StatusCode != HttpStatusCode.OK) return new(null, "execution_unavailable");
            if (response.Content.Headers.ContentType?.MediaType != "application/json" ||
                response.Content.Headers.ContentLength > ResponseLimit) return new(null, "invalid_execution_response");
            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[4096];
            int read;
            while ((read = await stream.ReadAsync(chunk, timeout.Token)) != 0)
            {
                if (buffer.Length + read > ResponseLimit) return new(null, "invalid_execution_response");
                buffer.Write(chunk, 0, read);
            }
            var bytes = buffer.ToArray();
            var result = JsonSerializer.Deserialize<PythonExecutionCompletion>(bytes, Wire) ?? throw new JsonException();
            using var source = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 32 });
            using var canonical = JsonDocument.Parse(CanonicalProposalService.Serialize(result));
            VerifyShape(source.RootElement, canonical.RootElement);
            Validate(result, workflowId, input);
            return new(result, null);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested) { return new(null, "execution_timeout"); }
        catch (OperationCanceledException) { throw; }
        catch (HttpRequestException) { return new(null, "execution_unavailable"); }
        catch (IOException) { return new(null, "execution_unavailable"); }
        catch (Exception error) when (error is JsonException or ArgumentException or InvalidOperationException or NullReferenceException or OverflowException)
        { return new(null, "invalid_execution_response"); }
    }

    // Require all typed fields and reject duplicates, unknown fields, integer enums and altered constant flags.
    // Pydantic emits decimal strings; typed decimal parsing preserves their precision.
    private static void VerifyShape(JsonElement source, JsonElement expected)
    {
        if (expected.ValueKind == JsonValueKind.Object)
        {
            if (source.ValueKind != JsonValueKind.Object) throw new JsonException();
            var properties = source.EnumerateObject().ToArray();
            if (properties.Length != expected.EnumerateObject().Count() || properties.Select(p => p.Name).Distinct().Count() != properties.Length)
                throw new JsonException();
            foreach (var property in expected.EnumerateObject())
            {
                if (!source.TryGetProperty(property.Name, out var value)) throw new JsonException();
                if (property.Name is "isReservation" or "timeZoneId" or "currency" or "schemaVersion" && value.GetRawText() != property.Value.GetRawText())
                    throw new JsonException();
                VerifyShape(value, property.Value);
            }
        }
        else if (expected.ValueKind == JsonValueKind.Array)
        {
            if (source.ValueKind != JsonValueKind.Array || source.GetArrayLength() != expected.GetArrayLength()) throw new JsonException();
            for (var i = 0; i < source.GetArrayLength(); i++) VerifyShape(source[i], expected[i]);
        }
        else if (source.ValueKind != expected.ValueKind && !(expected.ValueKind == JsonValueKind.Number && source.ValueKind == JsonValueKind.String))
            throw new JsonException();
    }

    internal static void Validate(PythonExecutionCompletion result, Guid id, PythonExecutionRequest input)
    {
        if (result.WorkflowId != id || result.ExecutionId != input.ExecutionId ||
            !CanonicalProposalService.Same(result.Requirements, input.Requirements)) throw new JsonException();
        if (result.Status != "AwaitingApproval")
        {
            if (result.Status is not ("Failed" or "RevalidationRequired" or "NeedsInput") ||
                result.Evidence is not null || result.SchedulingEvidence is not null ||
                result.ErrorCode is not ("execution_failed" or "execution_timeout" or "invalid_execution_response" or "revalidation_required" or "needs_input"))
                throw new JsonException();
            return;
        }
        var evidence = result.Evidence;
        var selected = evidence?.Current?.Selection;
        var schedule = result.SchedulingEvidence;
        if (selected is null || schedule is null || result.ErrorCode is not null ||
            !CanonicalProposalService.ValidEvidence(evidence, selected, DateTimeOffset.UtcNow, requireFresh: false) ||
            !evidence!.PriorTimestampAvailable || schedule.Candidates is not { Count: 1 } ||
            schedule.StudioId != selected.StudioId || schedule.PackageId != selected.PackageId || schedule.TimeZoneId != "Asia/Colombo" ||
            schedule.PackageDurationHours != evidence.Current!.PackageDurationHours ||
            schedule.RequiredDurationHours != evidence.Current.RequiredDurationHours || schedule.ExtraHours != selected.Customization.ExtraHours ||
            schedule.CheckedAtUtc.Offset != TimeSpan.Zero || schedule.CheckedAtUtc > evidence.CheckedAtUtc ||
            evidence.CheckedAtUtc - schedule.CheckedAtUtc >= TimeSpan.FromMinutes(5)) throw new JsonException();
        var slot = schedule.Candidates[0];
        if (slot.SlotId == Guid.Empty || slot.Date != selected.Date || slot.StartTime != selected.StartTime || slot.EndTime != selected.EndTime ||
            slot.EvidenceIds is not { Count: >= 1 and <= 50 } || slot.EvidenceIds.Any(s => string.IsNullOrWhiteSpace(s) || s.Length > 128) ||
            slot.EvidenceIds.Distinct().Count() != slot.EvidenceIds.Count ||
            (slot.EndTime - slot.StartTime).Ticks != decimal.Ceiling(schedule.RequiredDurationHours * TimeSpan.TicksPerHour)) throw new JsonException();
    }
}
