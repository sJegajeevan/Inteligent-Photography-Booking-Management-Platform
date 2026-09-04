namespace PhotographyBooking.Api.Models;

public class StudioPortfolio
{
	public Guid Id { get; set; } = Guid.NewGuid();
	public Guid StudioId { get; set; }
	public string Title { get; set; } = string.Empty;
	public string Description { get; set; } = string.Empty;
	public string ImageUrl { get; set; } = string.Empty;
	public string Category { get; set; } = string.Empty;
	public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
	public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
	public Studio Studio { get; set; } = null!;
	public ICollection<StudioPortfolioImage> Images { get; set; } = new List<StudioPortfolioImage>();
}
