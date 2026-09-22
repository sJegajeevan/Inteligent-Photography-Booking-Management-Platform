namespace PhotographyBooking.Api.Models;

public class StudioPortfolioImage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StudioPortfolioId { get; set; }
    public string ImageUrl { get; set; } = string.Empty;
    public int DisplayOrder { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public StudioPortfolio StudioPortfolio { get; set; } = null!;
}
