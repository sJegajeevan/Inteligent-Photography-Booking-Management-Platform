using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.StudioAvailability;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

namespace PhotographyBooking.Api.Tests;

public class StudioAvailabilityServiceTests
{
    private static ApplicationDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    private static StudioAvailabilityRequestDto CreateValidRequest(
        DateOnly? date = null,
        bool isAvailable = true)
    {
        return new StudioAvailabilityRequestDto
        {
            Date = date ?? DateOnly.FromDateTime(DateTime.Today.AddDays(1)),
            IsAvailable = isAvailable,
            StartTime = isAvailable ? new TimeOnly(9, 0) : null,
            EndTime = isAvailable ? new TimeOnly(17, 0) : null,
            Notes = "Test availability"
        };
    }

    private static async Task<(User User, Studio Studio)> SeedStudioAsync(
        ApplicationDbContext db,
        int userId = 101)
    {
        var user = new User
        {
            Id = userId,
            FullName = "Test Studio Owner",
            Email = $"studio{userId}@example.com",
            PasswordHash = "test-hash",
            Role = "Studio"
        };

        var studio = new Studio
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            StudioName = "Test Photography Studio",
            Description = "Test studio",
            Location = "Colombo",
            Address = "Test Address",
            ContactNumber = "0771234567",
            Email = user.Email,
            ExperienceYears = 5,
            PhotographyTypes = "Wedding",
            StartingPrice = 50000,
            User = user
        };

        db.Users.Add(user);
        db.Studios.Add(studio);
        await db.SaveChangesAsync();

        return (user, studio);
    }

    [Fact]
    public async Task CreateAsync_Should_Create_Availability_For_Studio_Owner()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);
        var service = new StudioAvailabilityService(db);

        var request = CreateValidRequest();

        var result = await service.CreateAsync(studio.UserId, request);

        Assert.Equal(AvailabilityWriteStatus.Success, result.Status);
        Assert.NotNull(result.Value);
        Assert.Equal(request.Date, result.Value!.Date);
        Assert.Equal(request.IsAvailable, result.Value.IsAvailable);
        Assert.Equal(1, await db.StudioAvailabilities.CountAsync());
    }

    [Fact]
    public async Task CreateAsync_Should_Return_StudioNotFound_For_Unknown_User()
    {
        await using var db = CreateDbContext();
        var service = new StudioAvailabilityService(db);

        var result = await service.CreateAsync(
            9999,
            CreateValidRequest());

        Assert.Equal(AvailabilityWriteStatus.StudioNotFound, result.Status);
        Assert.Empty(await db.StudioAvailabilities.ToListAsync());
    }

    [Fact]
    public async Task CreateAsync_Should_Reject_Duplicate_Date()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);

        var date = DateOnly.FromDateTime(DateTime.Today.AddDays(1));

        db.StudioAvailabilities.Add(new StudioAvailability
        {
            StudioId = studio.Id,
            Date = date,
            IsAvailable = true,
            StartTime = new TimeOnly(9, 0),
            EndTime = new TimeOnly(17, 0),
            Notes = "Existing record"
        });

        await db.SaveChangesAsync();

        var service = new StudioAvailabilityService(db);

        var result = await service.CreateAsync(
            studio.UserId,
            CreateValidRequest(date));

        Assert.Equal(AvailabilityWriteStatus.DuplicateDate, result.Status);
        Assert.Single(await db.StudioAvailabilities.ToListAsync());
    }

    [Fact]
    public async Task UpdateAsync_Should_Update_Owned_Availability()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);

        var availability = new StudioAvailability
        {
            StudioId = studio.Id,
            Date = DateOnly.FromDateTime(DateTime.Today.AddDays(1)),
            IsAvailable = true,
            StartTime = new TimeOnly(9, 0),
            EndTime = new TimeOnly(17, 0),
            Notes = "Original"
        };

        db.StudioAvailabilities.Add(availability);
        await db.SaveChangesAsync();

        var service = new StudioAvailabilityService(db);

        var newDate = DateOnly.FromDateTime(DateTime.Today.AddDays(2));

        var result = await service.UpdateAsync(
            studio.UserId,
            availability.Id,
            CreateValidRequest(newDate));

        Assert.Equal(AvailabilityWriteStatus.Success, result.Status);
        Assert.Equal(newDate, result.Value!.Date);
        Assert.Equal("Test availability", result.Value.Notes);
    }

    [Fact]
    public async Task UpdateAsync_Should_Return_RecordNotFound_For_Unknown_Record()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);
        var service = new StudioAvailabilityService(db);

        var result = await service.UpdateAsync(
            studio.UserId,
            Guid.NewGuid(),
            CreateValidRequest());

        Assert.Equal(AvailabilityWriteStatus.RecordNotFound, result.Status);
    }

    [Fact]
    public async Task DeleteAsync_Should_Delete_Owned_Availability()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);

        var availability = new StudioAvailability
        {
            StudioId = studio.Id,
            Date = DateOnly.FromDateTime(DateTime.Today.AddDays(1)),
            IsAvailable = true,
            StartTime = new TimeOnly(9, 0),
            EndTime = new TimeOnly(17, 0)
        };

        db.StudioAvailabilities.Add(availability);
        await db.SaveChangesAsync();

        var service = new StudioAvailabilityService(db);

        var result = await service.DeleteAsync(
            studio.UserId,
            availability.Id);

        Assert.True(result);
        Assert.Empty(await db.StudioAvailabilities.ToListAsync());
    }

    [Fact]
    public async Task DeleteAsync_Should_Return_False_For_Unknown_Record()
    {
        await using var db = CreateDbContext();
        var (_, studio) = await SeedStudioAsync(db);
        var service = new StudioAvailabilityService(db);

        var result = await service.DeleteAsync(
            studio.UserId,
            Guid.NewGuid());

        Assert.False(result);
    }

    [Fact]
    public async Task GetAllAsync_Should_Return_Owners_Availability_Ordered_By_Date()
    {
        await using var db = CreateDbContext();

        var (_, studio) = await SeedStudioAsync(db, 101);
        var (_, otherStudio) = await SeedStudioAsync(db, 102);

        db.StudioAvailabilities.AddRange(
            new StudioAvailability
            {
                StudioId = studio.Id,
                Date = DateOnly.FromDateTime(DateTime.Today.AddDays(3)),
                IsAvailable = true,
                StartTime = new TimeOnly(9, 0),
                EndTime = new TimeOnly(17, 0)
            },
            new StudioAvailability
            {
                StudioId = studio.Id,
                Date = DateOnly.FromDateTime(DateTime.Today.AddDays(1)),
                IsAvailable = true,
                StartTime = new TimeOnly(10, 0),
                EndTime = new TimeOnly(18, 0)
            },
            new StudioAvailability
            {
                StudioId = otherStudio.Id,
                Date = DateOnly.FromDateTime(DateTime.Today.AddDays(2)),
                IsAvailable = true,
                StartTime = new TimeOnly(8, 0),
                EndTime = new TimeOnly(16, 0)
            });

        await db.SaveChangesAsync();

        var service = new StudioAvailabilityService(db);

        var results = await service.GetAllAsync(studio.UserId);

        Assert.Equal(2, results.Count);
        Assert.Equal(
            DateOnly.FromDateTime(DateTime.Today.AddDays(1)),
            results[0].Date);
        Assert.Equal(
            DateOnly.FromDateTime(DateTime.Today.AddDays(3)),
            results[1].Date);
    }
}