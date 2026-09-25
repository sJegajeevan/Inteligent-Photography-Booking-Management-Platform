using PhotographyBooking.Api.Services;
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
    private readonly ApplicationDbContext _dbContext;

    private readonly StudioDiscoveryService _discovery;
    public PublicStudiosController(ApplicationDbContext dbContext, StudioDiscoveryService discovery)
    {
        _dbContext = dbContext;
        _discovery = discovery;
    }

    [HttpGet("nearby")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<ActionResult<IReadOnlyList<PublicStudioSummaryDto>>> GetNearby(
        [FromQuery] double? latitude, [FromQuery] double? longitude,
        [FromQuery] double? radiusKm, [FromQuery] string? search,
        [FromQuery] string? location, [FromQuery] string? service)
    {
        try
        {
            return Ok(WithPublicImages(await _discovery.NearbyAsync(latitude, longitude, radiusKm,
                search, location, service, HttpContext.RequestAborted)));
        }
        catch (ArgumentException error) { return BadRequest(new { message = error.Message }); }
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<PublicStudioSummaryDto>>> GetAll(
        [FromQuery] string? search, [FromQuery] string? location, [FromQuery] string? service) =>
        Ok(WithPublicImages(await _discovery.SearchAsync(search, location, service, HttpContext.RequestAborted)));

    private IReadOnlyList<PublicStudioSummaryDto> WithPublicImages(IReadOnlyList<PublicStudioSummaryDto> studios)
    {
        foreach (var studio in studios)
        {
            studio.ProfileImageUrl = ToPublicImageUrl(studio.ProfileImageUrl);
            studio.CoverImageUrl = ToPublicImageUrl(studio.CoverImageUrl);
        }
        return studios;
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
            PhotographyTypes = StudioDiscoveryService.SplitPhotographyTypes(studio.PhotographyTypes),
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
        var services = await _discovery.GetServicesAsync(studioId, HttpContext.RequestAborted);
        return services is null ? StudioNotFound() : Ok(services);
    }

    [HttpGet("{studioId:guid}/availability")]
    public async Task<ActionResult<IReadOnlyList<PublicStudioAvailabilityDto>>> GetAvailability(Guid studioId)
    {
        var availability = await _discovery.GetAvailabilityAsync(studioId, HttpContext.RequestAborted);
        return availability is null ? StudioNotFound() : Ok(availability);
    }

    private Task<bool> StudioExists(Guid studioId) =>
        _dbContext.Studios.AsNoTracking().AnyAsync(studio => studio.Id == studioId);

    private NotFoundObjectResult StudioNotFound() =>
        NotFound(new { message = "Studio was not found." });

    private string? ToPublicImageUrl(string? storedValue)
    {
        var value = StudioDiscoveryService.PublicImageReference(storedValue);
        if (value is null) return null;
        if (Uri.TryCreate(value, UriKind.Absolute, out var absoluteUri)) return absoluteUri.ToString();
        return $"{Request.Scheme}://{Request.Host}{Request.PathBase}{value}";
    }

}
