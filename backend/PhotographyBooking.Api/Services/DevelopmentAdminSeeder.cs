using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Services;

public static class DevelopmentAdminSeeder
{
    private const string AdminEmail = "admin@snapsync.local";

    public static async Task ProvisionAsync(IServiceProvider services, IConfiguration configuration, ILogger logger)
    {
        var adminPassword = configuration["DevelopmentAdmin:Password"];
        if (string.IsNullOrWhiteSpace(adminPassword))
        {
            throw new InvalidOperationException(
                "DevelopmentAdmin:Password is required in local user secrets to provision the development Admin account.");
        }

        await using var scope = services.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        var normalizedEmail = AdminEmail.ToLowerInvariant();
        if (await dbContext.Users.AnyAsync(user => user.Email.ToLower() == normalizedEmail))
        {
            logger.LogInformation("Development Admin account {Email} already exists; no changes made.", AdminEmail);
            return;
        }

        dbContext.Users.Add(new User
        {
            FullName = "SnapSync Admin",
            Email = normalizedEmail,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPassword),
            Role = "Admin",
            CreatedAt = DateTime.UtcNow
        });

        await dbContext.SaveChangesAsync();
        logger.LogInformation("Development Admin account {Email} was created.", AdminEmail);
    }
}