namespace PhotographyBooking.Api.DTOs.PublicStudios;

public class PublicStudioSummaryDto
{
    public Guid Id { get; set; }
    public string StudioName { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string DescriptionSummary { get; set; } = string.Empty;
    public string? ProfileImageUrl { get; set; }
    public string? CoverImageUrl { get; set; }
    public IReadOnlyList<string> PhotographyTypes { get; set; } = [];
    public decimal StartingPrice { get; set; }
}

public class PublicStudioDetailDto
{
    public Guid Id { get; set; }
    public string StudioName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string ContactNumber { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int ExperienceYears { get; set; }
    public IReadOnlyList<string> PhotographyTypes { get; set; } = [];
    public decimal StartingPrice { get; set; }
    public string? ProfileImageUrl { get; set; }
    public string? CoverImageUrl { get; set; }
}

public class PublicPortfolioAlbumDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public DateOnly? EventDate { get; set; }
    public string? CoverImageUrl { get; set; }
    public int PhotoCount { get; set; }
    public IReadOnlyList<PublicPortfolioImageDto> Images { get; set; } = [];
}

public class PublicPortfolioImageDto
{
    public Guid Id { get; set; }
    public string ImageUrl { get; set; } = string.Empty;
}

public class PublicStudioServiceDto
{
    public Guid Id { get; set; }
    public string ServiceName { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public IReadOnlyList<string> PackageDetails { get; set; } = [];
    public decimal StartingPrice { get; set; }
}

public class PublicStudioAvailabilityDto
{
    public DateOnly Date { get; set; }
    public bool IsAvailable { get; set; }
    public TimeOnly? StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }
}
