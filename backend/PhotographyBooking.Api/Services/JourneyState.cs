using System.Text.Json;
using System.Text.Json.Serialization;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

// Deliberately mirrors the deployed bounded event vocabulary. Null optional fields are omitted.
public sealed record JourneyData
{
    public int V { get; init; } = 1;
    public int Revision { get; init; }
    public int Sequence { get; init; }
    public Guid OperationId { get; init; }
    public required string Kind { get; init; }
    public Guid? StudioId { get; init; }
    public Guid? PackageId { get; init; }
    public Guid? SourceEventId { get; init; }
    public Guid? OptionEventId { get; init; }
    public Guid[]? OptionEventIds { get; init; }
    public int? Rank { get; init; }
    public int? ExtraHours { get; init; }
    public string? QuotedPrice { get; init; }
    public string? DurationHours { get; init; }
    public string? Date { get; init; }
    public string? StartTime { get; init; }
    public string? EndTime { get; init; }
    public string? ExpiresAt { get; init; }
    public string? Reason { get; init; }
    public string? ErrorCode { get; init; }
    public string? InvalidatesFrom { get; init; }
}

public sealed record JourneyEntry(AiWorkflowEvent Event, JourneyData Data);

public sealed class JourneyState
{
    public static readonly string[] Stages = ["StudioMatching", "PackageRecommendation", "Scheduling", "Validation"];
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public List<JourneyEntry> Entries { get; } = [];
    public Dictionary<string, List<JourneyEntry>> Options { get; } = [];
    public Dictionary<string, JourneyEntry> Selections { get; } = [];
    public int Revision => Entries.LastOrDefault()?.Data.Revision ?? 1;
    public int Sequence => Entries.LastOrDefault()?.Data.Sequence ?? 0;
    public string Stage { get; private set; } = Stages[0];
    public JourneyEntry? Running { get; private set; }
    public JourneyEntry? Validated { get; private set; }
    public string? ErrorCode { get; private set; }

    public static JourneyState Read(AiWorkflow workflow)
    {
        var state = new JourneyState();
        foreach (var entry in workflow.Events.Where(e => e.EventType == "JourneyV1")
            .Select(e => new JourneyEntry(e, JsonSerializer.Deserialize<Dictionary<string, JourneyData>>(e.DetailsJson!, Json)!["journey"]))
            .OrderBy(e => e.Data.Sequence))
        {
            if (entry.Data.Sequence != state.Sequence + 1 || entry.Data.Revision < state.Revision)
                throw new InvalidOperationException("Invalid journey history.");
            state.Entries.Add(entry);
            var data = entry.Data;
            if (data.Kind is "selected" or "rewound")
            {
                var first = Array.IndexOf(Stages, data.InvalidatesFrom!);
                if (first < 0) throw new InvalidOperationException("Invalid invalidation.");
                foreach (var stage in Stages.Skip(first)) { state.Options.Remove(stage); state.Selections.Remove(stage); }
                state.Validated = null;
                state.Running = null;
                state.ErrorCode = null;
                state.Stage = data.InvalidatesFrom!;
                if (data.Kind == "selected")
                {
                    var option = state.Options.GetValueOrDefault(entry.Event.StepName)?.SingleOrDefault(o => o.Event.Id == data.OptionEventId)
                        ?? throw new InvalidOperationException("Invalid selected option.");
                    state.Selections[entry.Event.StepName] = option;
                }
            }
            if (data.Kind == "started") { state.Running = entry; state.Stage = entry.Event.StepName; state.ErrorCode = null; }
            if (data.Kind == "completed")
            {
                state.Options[entry.Event.StepName] = data.OptionEventIds!.Select(id => state.Entries.Single(e => e.Event.Id == id)).ToList();
                state.Running = null;
            }
            if (data.Kind == "failed") { state.Running = null; state.ErrorCode = data.ErrorCode; }
            if (data.Kind == "validated") { state.Running = null; state.Validated = entry; }
        }
        return state;
    }

    public static AiWorkflowEvent Append(AiWorkflow workflow, string stage, JourneyData data, DateTime now)
    {
        if (!Stages.Contains(stage) || data.OperationId == Guid.Empty || data.Revision is < 1 or > 999999999 ||
            data.Sequence is < 1 or > 999999999) throw new InvalidOperationException("Invalid event bounds.");
        var json = JsonSerializer.Serialize(new { journey = data }, Json);
        // Leave space for PostgreSQL's JSONB whitespace representation.
        if (System.Text.Encoding.UTF8.GetByteCount(json) > 3500) throw new InvalidOperationException("Oversized event.");
        var item = new AiWorkflowEvent { WorkflowId = workflow.Id, EventType = "JourneyV1", StepName = stage,
            Success = data.Kind != "failed", Summary = $"{stage}: {data.Kind}.", DetailsJson = json, CreatedAt = now };
        workflow.Events.Add(item);
        return item;
    }
}
