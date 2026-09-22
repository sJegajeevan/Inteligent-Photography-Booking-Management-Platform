using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Studio;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public class StudioService
{
    private readonly ApplicationDbContext _dbContext;
    public StudioService(ApplicationDbContext dbContext) => _dbContext = dbContext;

    public async Task<StudioResponseDto?> GetProfileAsync(int userId)
    {
        var studio = await _dbContext.Studios.AsNoTracking().SingleOrDefaultAsync(s => s.UserId == userId);
        return studio is null ? null : ToResponse(studio);
    }

    public async Task<(StudioResponseDto Profile, bool Created)> UpsertProfileAsync(int userId, UpdateStudioDto request)
    {
        var studio = await _dbContext.Studios.SingleOrDefaultAsync(s => s.UserId == userId);
        var created = studio is null;
        if (studio is null) { studio = new Studio { UserId = userId }; _dbContext.Studios.Add(studio); }
        studio.StudioName = request.StudioName.Trim(); studio.Description = request.Description.Trim();
        studio.Location = request.Location.Trim(); studio.Address = request.Address.Trim();
        studio.ContactNumber = request.ContactNumber.Trim();
        studio.Email = request.Email.Trim().ToLowerInvariant();
        studio.ExperienceYears = request.ExperienceYears;
        studio.PhotographyTypes = request.PhotographyTypes.Trim();
        studio.StartingPrice = request.StartingPrice;
        studio.LogoUrl = request.LogoUrl.Trim();
        studio.CoverPhotoUrl = request.CoverPhotoUrl.Trim();
        await _dbContext.SaveChangesAsync();
        return (ToResponse(studio), created);
    }

    public async Task<bool> DeleteProfileAsync(int userId)
    {
        var studio = await _dbContext.Studios.SingleOrDefaultAsync(s => s.UserId == userId);
        if (studio is null) return false;
        _dbContext.Studios.Remove(studio);
        await _dbContext.SaveChangesAsync();
        return true;
    }

    private static StudioResponseDto ToResponse(Studio studio) => new()
    {
        Id = studio.Id, StudioName = studio.StudioName, Description = studio.Description,
        Location = studio.Location, Address = studio.Address, ContactNumber = studio.ContactNumber,
        Email = studio.Email, ExperienceYears = studio.ExperienceYears,
        PhotographyTypes = studio.PhotographyTypes, StartingPrice = studio.StartingPrice,
        LogoUrl = studio.LogoUrl, CoverPhotoUrl = studio.CoverPhotoUrl
    };
}
