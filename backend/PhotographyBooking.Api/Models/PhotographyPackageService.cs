namespace PhotographyBooking.Api.Models;

public class PhotographyPackageService
{
    public Guid PhotographyPackageId { get; set; }
    public PhotographyPackage PhotographyPackage { get; set; } = null!;
    public Guid StudioServiceId { get; set; }
    public StudioService StudioService { get; set; } = null!;
}
