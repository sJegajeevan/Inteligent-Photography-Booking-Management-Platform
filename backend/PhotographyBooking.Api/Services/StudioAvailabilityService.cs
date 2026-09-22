using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.StudioAvailability;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public enum AvailabilityWriteStatus { Success, StudioNotFound, RecordNotFound, DuplicateDate }
public record AvailabilityWriteResult(AvailabilityWriteStatus Status, StudioAvailabilityResponseDto? Value = null);

public class StudioAvailabilityService
{
    private readonly ApplicationDbContext _dbContext;
    public StudioAvailabilityService(ApplicationDbContext dbContext) => _dbContext = dbContext;

    public async Task<IReadOnlyList<StudioAvailabilityResponseDto>> GetAllAsync(int userId) =>
        await _dbContext.StudioAvailabilities.AsNoTracking()
            .Where(item => item.Studio.UserId == userId)
            .OrderBy(item => item.Date)
            .Select(item => ToResponse(item))
            .ToListAsync();

    public async Task<AvailabilityWriteResult> CreateAsync(int userId, StudioAvailabilityRequestDto request)
    {
        var studioId = await _dbContext.Studios.Where(s => s.UserId == userId).Select(s => (Guid?)s.Id).SingleOrDefaultAsync();
        if (studioId is null) return new(AvailabilityWriteStatus.StudioNotFound);
        if (await _dbContext.StudioAvailabilities.AnyAsync(a => a.StudioId == studioId && a.Date == request.Date!.Value))
            return new(AvailabilityWriteStatus.DuplicateDate);

        var item = new StudioAvailability { StudioId = studioId.Value };
        Apply(item, request);
        _dbContext.StudioAvailabilities.Add(item);
        await _dbContext.SaveChangesAsync();
        return new(AvailabilityWriteStatus.Success, ToResponse(item));
    }

    public async Task<AvailabilityWriteResult> UpdateAsync(int userId, Guid id, StudioAvailabilityRequestDto request)
    {
        var item = await _dbContext.StudioAvailabilities.SingleOrDefaultAsync(a => a.Id == id && a.Studio.UserId == userId);
        if (item is null) return new(AvailabilityWriteStatus.RecordNotFound);
        if (await _dbContext.StudioAvailabilities.AnyAsync(a => a.StudioId == item.StudioId && a.Date == request.Date!.Value && a.Id != id))
            return new(AvailabilityWriteStatus.DuplicateDate);
        Apply(item, request);
        await _dbContext.SaveChangesAsync();
        return new(AvailabilityWriteStatus.Success, ToResponse(item));
    }

    public async Task<bool> DeleteAsync(int userId, Guid id)
    {
        var item = await _dbContext.StudioAvailabilities.SingleOrDefaultAsync(a => a.Id == id && a.Studio.UserId == userId);
        if (item is null) return false;
        _dbContext.StudioAvailabilities.Remove(item);
        await _dbContext.SaveChangesAsync();
        return true;
    }

    private static void Apply(StudioAvailability item, StudioAvailabilityRequestDto request)
    {
        item.Date = request.Date!.Value;
        item.IsAvailable = request.IsAvailable!.Value;
        item.StartTime = request.IsAvailable.Value ? request.StartTime : null;
        item.EndTime = request.IsAvailable.Value ? request.EndTime : null;
        item.Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim();
    }

    private static StudioAvailabilityResponseDto ToResponse(StudioAvailability item) => new()
    {
        Id = item.Id, StudioId = item.StudioId, Date = item.Date, IsAvailable = item.IsAvailable,
        StartTime = item.StartTime, EndTime = item.EndTime, Notes = item.Notes
    };
}
