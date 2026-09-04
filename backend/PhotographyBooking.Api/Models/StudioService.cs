namespace PhotographyBooking.Api.Models;

public class StudioService
{
	public Guid Id { get; set; } = Guid.NewGuid();
	public Guid StudioId { get; set; }
	public string ServiceName { get; set; } = string.Empty;
	public string Description { get; set; } = string.Empty;
	public string[] PackageDetails { get; set; } = [];
	public decimal StartingPrice { get; set; }
	public Studio Studio { get; set; } = null!;
}
