using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PublicStudios;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/public/studios")]
[AllowAnonymous]
public class PublicStudiosController : ControllerBase
{
    private const int SummaryLength = 180;
    private readonly ApplicationDbContext _dbContext;

    public PublicStudiosController(ApplicationDbContext dbContext) => _dbContext = dbContext;

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PublicStudioSummaryDto>>> GetAll(
        [FromQuery] string? search,
        [FromQuery] string? location,
        [FromQuery] string? service)
    {
        var query = _dbContext.Studios.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLower();
            query = query.Where(studio =>
                studio.StudioName.ToLower().Contains(term) ||
                studio.Description.ToLower().Contains(term) ||
                studio.PhotographyTypes.ToLower().Contains(term));
        }

        if (!string.IsNullOrWhiteSpace(location))
        {
            var term = location.Trim().ToLower();
            query = query.Where(studio => studio.Location.ToLower().Contains(term));
        }

        if (!string.IsNullOrWhiteSpace(service))
        {
            var term = service.Trim().ToLower();
            query = query.Where(studio => _dbContext.StudioServices.Any(item =>
                item.StudioId == studio.Id && item.ServiceName.ToLower().Contains(term)));
        }

        var studios = await query.OrderBy(studio => studio.StudioName).ToListAsync();
        return Ok(studios.Select(studio => new PublicStudioSummaryDto
        {
            Id = studio.Id,
            StudioName = studio.StudioName,
            Location = studio.Location,
            DescriptionSummary = Summarize(studio.Description),
            ProfileImageUrl = ToPublicImageUrl(studio.LogoUrl),
            CoverImageUrl = ToPublicImageUrl(studio.CoverPhotoUrl),
            PhotographyTypes = SplitPhotographyTypes(studio.PhotographyTypes),
            StartingPrice = studio.StartingPrice
        }).ToList());
    }

    [HttpGet("{studioId:guid}")]
    public async Task<ActionResult<PublicStudioDetailDto>> GetById(Guid studioId)
    {
        var studio = await _dbContext.Studios.AsNoTracking().SingleOrDefaultAsync(item => item.Id == studioId);
        if (studio is null) return StudioNotFound();

        return Ok(new PublicStudioDetailDto
        {
            Id = studio.Id,
            StudioName = studio.StudioName,
            Description = studio.Description,
            Location = studio.Location,
            Address = studio.Address,
            ContactNumber = studio.ContactNumber,
            Email = studio.Email,
            ExperienceYears = studio.ExperienceYears,
            PhotographyTypes = SplitPhotographyTypes(studio.PhotographyTypes),
            StartingPrice = studio.StartingPrice,
            ProfileImageUrl = ToPublicImageUrl(studio.LogoUrl),
            CoverImageUrl = ToPublicImageUrl(studio.CoverPhotoUrl)
        });
    }

    [HttpGet("{studioId:guid}/portfolio")]
    public async Task<ActionResult<IReadOnlyList<PublicPortfolioAlbumDto>>> GetPortfolio(Guid studioId)
    {
        if (!await StudioExists(studioId)) return StudioNotFound();

        var albums = await _dbContext.StudioPortfolios.AsNoTracking()
            .Include(album => album.Images)
            .Where(album => album.StudioId == studioId)
            .OrderByDescending(album => album.CreatedAt)
            .ToListAsync();

        return Ok(albums.Select(album =>
        {
            var images = album.Images.OrderBy(image => image.DisplayOrder)
                .Select(image => new PublicPortfolioImageDto
                {
                    Id = image.Id,
                    ImageUrl = ToPublicImageUrl(image.ImageUrl) ?? string.Empty
                })
                .Where(image => image.ImageUrl.Length > 0)
                .ToList();

            return new PublicPortfolioAlbumDto
            {
                Id = album.Id,
                Title = album.Title,
                Category = album.Category,
                Description = album.Description,
                // The current portfolio entity has no event-date field. Do not mislabel its upload timestamp.
                EventDate = null,
                CoverImageUrl = images.FirstOrDefault()?.ImageUrl ?? ToPublicImageUrl(album.ImageUrl),
                PhotoCount = images.Count,
                Images = images
            };
        }).ToList());
    }

    [HttpGet("{studioId:guid}/services")]
    public async Task<ActionResult<IReadOnlyList<PublicStudioServiceDto>>> GetServices(Guid studioId)
    {
        if (!await StudioExists(studioId)) return StudioNotFound();

        var services = await _dbContext.StudioServices.AsNoTracking()
            .Where(item => item.StudioId == studioId)
            .OrderBy(item => item.ServiceName)
            .Select(item => new PublicStudioServiceDto
            {
                Id = item.Id,
                ServiceName = item.ServiceName,
                Description = item.Description,
                PackageDetails = item.PackageDetails,
                StartingPrice = item.StartingPrice
            })
            .ToListAsync();
        return Ok(services);
    }

    [HttpGet("{studioId:guid}/availability")]
    public async Task<ActionResult<IReadOnlyList<PublicStudioAvailabilityDto>>> GetAvailability(Guid studioId)
    {
        if (!await StudioExists(studioId)) return StudioNotFound();

        var availability = await _dbContext.StudioAvailabilities.AsNoTracking()
            .Where(item => item.StudioId == studioId)
            .OrderBy(item => item.Date)
            .Select(item => new PublicStudioAvailabilityDto
            {
                Date = item.Date,
                IsAvailable = item.IsAvailable,
                StartTime = item.StartTime,
                EndTime = item.EndTime
            })
            .ToListAsync();
        return Ok(availability);
    }

    private Task<bool> StudioExists(Guid studioId) =>
        _dbContext.Studios.AsNoTracking().AnyAsync(studio => studio.Id == studioId);

    private NotFoundObjectResult StudioNotFound() =>
        NotFound(new { message = "Studio was not found." });

    private string? ToPublicImageUrl(string? storedValue)
    {
        if (string.IsNullOrWhiteSpace(storedValue)) return null;
        var value = storedValue.Trim().Replace('\\', '/');

        if (Uri.TryCreate(value, UriKind.Absolute, out var absoluteUri))
            return absoluteUri.Scheme is "http" or "https" ? absoluteUri.ToString() : null;

        // Only known web-relative paths are exposed; local drive and arbitrary filesystem paths are rejected.
        if (!value.StartsWith('/') || value.StartsWith("//") || value.Contains("..")) return null;
        return $"{Request.Scheme}://{Request.Host}{Request.PathBase}{value}";
    }

    private static IReadOnlyList<string> SplitPhotographyTypes(string value) =>
        value.Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

    private static string Summarize(string value) =>
        value.Length <= SummaryLength ? value : $"{value[..(SummaryLength - 1)].TrimEnd()}…";
}
