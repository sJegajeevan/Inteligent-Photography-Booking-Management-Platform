namespace PhotographyBooking.Api.DTOs.StudioServices;

public class StudioServiceResponseDto
{
    public Guid Id { get; set; }
    public Guid StudioId { get; set; }
    public string ServiceName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public IReadOnlyList<string> PackageDetails { get; set; } = [];
    public decimal StartingPrice { get; set; }
}
