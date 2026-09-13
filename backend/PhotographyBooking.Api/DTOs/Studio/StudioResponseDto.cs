namespace PhotographyBooking.Api.DTOs.Studio;

public class StudioResponseDto
{
    public Guid Id { get; set; }
    public string StudioName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string ContactNumber { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int ExperienceYears { get; set; }
    public string PhotographyTypes { get; set; } = string.Empty;
    public decimal StartingPrice { get; set; }
    public string LogoUrl { get; set; } = string.Empty;
    public string CoverPhotoUrl { get; set; } = string.Empty;
}
