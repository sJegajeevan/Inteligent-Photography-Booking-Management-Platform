namespace PhotographyBooking.Api.DTOs.Scheduling;

public sealed record SchedulingCandidateDto(Guid SlotId, DateOnly Date, TimeOnly StartTime,
    TimeOnly EndTime, IReadOnlyList<string> EvidenceIds);

/// <summary>Point-in-time evidence only. IDs are ephemeral, never persisted or booking authorizations.</summary>
public sealed record SchedulingCandidateResponseDto(Guid StudioId, Guid PackageId, string TimeZoneId,
    decimal PackageDurationHours, int ExtraHours, decimal RequiredDurationHours,
    DateTimeOffset CheckedAtUtc, bool Truncated, IReadOnlyList<SchedulingCandidateDto> Candidates)
{
    public bool IsReservation => false;
}
