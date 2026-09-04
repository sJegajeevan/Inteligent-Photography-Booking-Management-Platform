using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Http;

namespace PhotographyBooking.Api.DTOs.StudioPortfolio;

public class StudioPortfolioRequestDto
{
    [Required, StringLength(160, MinimumLength = 2)]
    public string Title { get; set; } = string.Empty;

    [StringLength(1000)]
    public string Description { get; set; } = string.Empty;

    [Required, StringLength(60, MinimumLength = 2)]
    public string Category { get; set; } = string.Empty;

    public List<IFormFile> Photos { get; set; } = [];

    public List<Guid> RemovedImageIds { get; set; } = [];
}
