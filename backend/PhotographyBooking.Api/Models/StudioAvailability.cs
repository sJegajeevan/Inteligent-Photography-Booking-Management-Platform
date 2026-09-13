namespace PhotographyBooking.Api.Models;

public class StudioAvailability
{
	public Guid Id { get; set; } = Guid.NewGuid();
	public Guid StudioId { get; set; }
	public DateOnly Date { get; set; }
	public bool IsAvailable { get; set; }
	public TimeOnly? StartTime { get; set; }
	public TimeOnly? EndTime { get; set; }
	public string? Notes { get; set; }
	public Studio Studio { get; set; } = null!;
}
