namespace PhotographyBooking.Api.DTOs.StudioPortfolio;

public class StudioPortfolioResponseDto
{
    public Guid Id { get; set; }
    public Guid StudioId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string ImageUrl { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public IReadOnlyList<StudioPortfolioImageResponseDto> Images { get; set; } = [];
}

public class StudioPortfolioImageResponseDto
{
    public Guid Id { get; set; }
    public string ImageUrl { get; set; } = string.Empty;
    public int DisplayOrder { get; set; }
}
