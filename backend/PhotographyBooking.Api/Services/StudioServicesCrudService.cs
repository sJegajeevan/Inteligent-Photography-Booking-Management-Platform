using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.StudioServices;
using StudioServiceEntity = PhotographyBooking.Api.Models.StudioService;

namespace PhotographyBooking.Api.Services;

public class StudioServicesCrudService
{
    private readonly ApplicationDbContext _dbContext;

    public StudioServicesCrudService(ApplicationDbContext dbContext) => _dbContext = dbContext;

    public async Task<IReadOnlyList<StudioServiceResponseDto>> GetAllAsync(int userId) =>
        await _dbContext.StudioServices.AsNoTracking()
            .Where(service => service.Studio.UserId == userId)
            .OrderBy(service => service.ServiceName)
            .Select(service => ToResponse(service))
            .ToListAsync();

    public async Task<StudioServiceResponseDto?> CreateAsync(int userId, StudioServiceRequestDto request)
    {
        var studioId = await _dbContext.Studios.Where(studio => studio.UserId == userId)
            .Select(studio => (Guid?)studio.Id).SingleOrDefaultAsync();
        if (studioId is null) return null;

        var service = new StudioServiceEntity
        {
            StudioId = studioId.Value,
            ServiceName = request.ServiceName.Trim(),
            Description = request.Description.Trim(),
            PackageDetails = NormalizePackageDetails(request.PackageDetails),
            StartingPrice = request.StartingPrice
        };
        _dbContext.StudioServices.Add(service);
        await _dbContext.SaveChangesAsync();
        return ToResponse(service);
    }

    public async Task<StudioServiceResponseDto?> UpdateAsync(int userId, Guid id, StudioServiceRequestDto request)
    {
        var service = await _dbContext.StudioServices
            .SingleOrDefaultAsync(item => item.Id == id && item.Studio.UserId == userId);
        if (service is null) return null;

        service.ServiceName = request.ServiceName.Trim();
        service.Description = request.Description.Trim();
        service.PackageDetails = NormalizePackageDetails(request.PackageDetails);
        service.StartingPrice = request.StartingPrice;
        await _dbContext.SaveChangesAsync();
        return ToResponse(service);
    }

    public async Task<bool> DeleteAsync(int userId, Guid id)
    {
        var service = await _dbContext.StudioServices
            .SingleOrDefaultAsync(item => item.Id == id && item.Studio.UserId == userId);
        if (service is null) return false;
        _dbContext.StudioServices.Remove(service);
        await _dbContext.SaveChangesAsync();
        return true;
    }

    private static StudioServiceResponseDto ToResponse(StudioServiceEntity service) => new()
    {
        Id = service.Id,
        StudioId = service.StudioId,
        ServiceName = service.ServiceName,
        Description = service.Description,
        PackageDetails = service.PackageDetails ?? [],
        StartingPrice = service.StartingPrice
    };

    private static string[] NormalizePackageDetails(IEnumerable<string>? packageDetails) =>
        packageDetails?
            .Where(detail => !string.IsNullOrWhiteSpace(detail))
            .Select(detail => detail.Trim())
            .ToArray() ?? [];
}
