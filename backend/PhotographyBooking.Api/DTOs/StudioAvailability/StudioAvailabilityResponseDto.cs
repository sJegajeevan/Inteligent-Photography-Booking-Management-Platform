namespace PhotographyBooking.Api.DTOs.StudioAvailability;

public class StudioAvailabilityResponseDto
{
    public Guid Id { get; set; }
    public Guid StudioId { get; set; }
    public DateOnly Date { get; set; }
    public bool IsAvailable { get; set; }
    public TimeOnly? StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }
    public string? Notes { get; set; }
}
