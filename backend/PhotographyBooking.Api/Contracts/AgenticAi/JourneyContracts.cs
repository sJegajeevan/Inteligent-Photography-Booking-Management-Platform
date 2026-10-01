using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class JourneyAction
{
    public Guid OperationId { get; init; }
    [Range(1, 999999998)] public int Revision { get; init; }
    public Guid? OptionEventId { get; init; }
}

public sealed record JourneyOption(Guid EventId, string Stage, Guid? StudioId, Guid? PackageId,
    int Rank, string Name, string? ImageUrl, string? Location, string? Specialties,
    string? Reason, decimal? Price, decimal? DurationHours, int? ExtraHours, IReadOnlyList<string>? Services,
    string? Date, string? StartTime, string? EndTime);

public sealed record JourneyView(int Revision, string Stage, bool Busy, bool Validated, bool Submitted,
    string? ErrorCode, Guid? StudioOptionId, Guid? PackageOptionId, Guid? ScheduleOptionId,
    IReadOnlyList<JourneyOption> Options);
