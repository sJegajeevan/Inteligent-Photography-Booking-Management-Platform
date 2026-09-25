using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PublicStudios;

namespace PhotographyBooking.Api.Services;

/// <summary>Read-only public discovery. Image references are safe but relative; HTTP adapters resolve their origin.</summary>
public sealed class StudioDiscoveryService(ApplicationDbContext dbContext, DistanceService distanceService)
{
    private const int SummaryLength = 180;
    private readonly ApplicationDbContext _dbContext = dbContext;
    private readonly DistanceService _distanceService = distanceService;

    public async Task<IReadOnlyList<PublicStudioSummaryDto>> SearchAsync(
        string? search = null, string? location = null, string? service = null, CancellationToken ct = default)
    {
        var studios = await FilterStudios(search, location, service).OrderBy(s => s.StudioName).ToListAsync(ct);
        return studios.Select(ToSummary).ToList();
    }

    public async Task<IReadOnlyList<PublicStudioSummaryDto>> NearbyAsync(
        double? latitude, double? longitude, double? radiusKm = null,
        string? search = null, string? location = null, string? service = null, CancellationToken ct = default)
    {
        if (!latitude.HasValue || !longitude.HasValue ||
            !DistanceService.IsValidCoordinate(latitude.Value, longitude.Value))
            throw new ArgumentException("Supply latitude (-90 to 90) and longitude (-180 to 180).");
        if (radiusKm.HasValue && (!double.IsFinite(radiusKm.Value) || radiusKm <= 0 || radiusKm > 500))
            throw new ArgumentException("Radius must be greater than 0 and at most 500 km.");

        var query = FilterStudios(search, location, service).Where(studio =>
            studio.Latitude != null && studio.Longitude != null &&
            studio.Latitude >= -90 && studio.Latitude <= 90 &&
            studio.Longitude >= -180 && studio.Longitude <= 180);
        // Stream candidates instead of materializing private entity data into the response.
        var results = new List<PublicStudioSummaryDto>();
        await foreach (var studio in query.AsAsyncEnumerable().WithCancellation(ct))
        {
            var distance = _distanceService.CalculateKilometers(latitude.Value, longitude.Value,
                (double)studio.Latitude!.Value, (double)studio.Longitude!.Value);
            if (radiusKm.HasValue && distance > radiusKm.Value) continue;
            var summary = ToSummary(studio);
            summary.DistanceKm = distance;
            results.Add(summary);
        }
        return results.OrderBy(studio => studio.DistanceKm)
            .ThenBy(studio => studio.StudioName).ThenBy(studio => studio.Id).ToList();
    }

    public async Task<IReadOnlyList<PublicStudioServiceDto>?> GetServicesAsync(Guid studioId, CancellationToken ct = default)
    {
        if (!await _dbContext.Studios.AnyAsync(s => s.Id == studioId, ct)) return null;
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
            .ToListAsync(ct);
        return services;
    }

    // Published windows, not a promise that the entire window is free of bookings.
    public async Task<IReadOnlyList<PublicStudioAvailabilityDto>?> GetAvailabilityAsync(Guid studioId, CancellationToken ct = default)
    {
        if (!await _dbContext.Studios.AnyAsync(s => s.Id == studioId, ct)) return null;
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
            .ToListAsync(ct);
        return availability;
    }

    private IQueryable<PhotographyBooking.Api.Models.Studio> FilterStudios(string? search, string? location, string? service) =>
        ApplyFilters(_dbContext.Studios.AsNoTracking(), _dbContext.StudioServices.AsNoTracking(), search, location, service);

    internal static IQueryable<PhotographyBooking.Api.Models.Studio> ApplyFilters(
        IQueryable<PhotographyBooking.Api.Models.Studio> query,
        IQueryable<PhotographyBooking.Api.Models.StudioService> services,
        string? search, string? location, string? service)
    {

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
            query = query.Where(studio => services.Any(item =>
                item.StudioId == studio.Id && item.ServiceName.ToLower().Contains(term)));
        }

        return query;
    }

    internal static PublicStudioSummaryDto ToSummary(PhotographyBooking.Api.Models.Studio studio) => new()
        {
            Id = studio.Id,
            StudioName = studio.StudioName,
            Location = studio.Location,
            DescriptionSummary = Summarize(studio.Description),
            ProfileImageUrl = PublicImageReference(studio.LogoUrl),
            CoverImageUrl = PublicImageReference(studio.CoverPhotoUrl),
            PhotographyTypes = SplitPhotographyTypes(studio.PhotographyTypes),
            StartingPrice = studio.StartingPrice
        };

    internal static IReadOnlyList<string> SplitPhotographyTypes(string value) =>
        value.Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

    private static string Summarize(string value) =>
        value.Length <= SummaryLength ? value : $"{value[..(SummaryLength - 1)].TrimEnd()}â€¦";

    internal static string? PublicImageReference(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        value = value.Trim().Replace('\\', '/');
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri))
            return uri.Scheme is "http" or "https" ? uri.ToString() : null;
        return value.StartsWith('/') && !value.StartsWith("//") && !value.Contains("..") ? value : null;
    }
}
