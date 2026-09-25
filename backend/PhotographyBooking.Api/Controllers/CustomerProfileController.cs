using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Customers;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Authorize(Roles = "Customer")]
[Route("api/customer/profile")]
public class CustomerProfileController(ApplicationDbContext db, IWebHostEnvironment environment) : ControllerBase
{
    private const int MaxPhotoSize = 5 * 1024 * 1024;

    private Task<User?> CurrentCustomer() => int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)
        ? db.Users.SingleOrDefaultAsync(u => u.Id == id && u.Role == "Customer")
        : Task.FromResult<User?>(null);

    private static CustomerProfileResponse Profile(User user) => new(user.Id, user.FullName,
        user.Email, user.Role, user.PhoneNumber, user.ProfilePhotoUrl);

    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var user = await CurrentCustomer();
        return user is null ? Unauthorized() : Ok(Profile(user));
    }

    [HttpPut]
    public async Task<IActionResult> Update(UpdateCustomerProfileRequest request)
    {
        var user = await CurrentCustomer();
        if (user is null) return Unauthorized();
        var email = request.Email.Trim().ToLowerInvariant();
        if (await db.Users.AnyAsync(u => u.Id != user.Id && u.Email.ToLower() == email))
            return Conflict(new { message = "An account with this email already exists." });
        user.FullName = request.FullName.Trim();
        user.Email = email;
        user.PhoneNumber = string.IsNullOrWhiteSpace(request.PhoneNumber) ? null : request.PhoneNumber.Trim();
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException ex) when (ex.InnerException is PostgresException { SqlState: "23505" })
        {
            return Conflict(new { message = "An account with this email already exists." });
        }
        return Ok(Profile(user));
    }

    [HttpPut("change-password")]
    [Microsoft.AspNetCore.RateLimiting.EnableRateLimiting("CustomerChangePassword")]
    [RequestSizeLimit(32768)]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request, CancellationToken ct)
    {
        // BCrypt passwords must not silently exceed its 72-byte input limit.
        if (System.Text.Encoding.UTF8.GetByteCount(request.NewPassword) > 72)
            return BadRequest(new { message = "New password must be at most 72 UTF-8 bytes. Use fewer characters." });

        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) return Unauthorized();
        var account = await db.Users.AsNoTracking()
            .Where(u => u.Id == id && u.Role == "Customer")
            .Select(u => new { u.Id, u.PasswordHash }).SingleOrDefaultAsync(ct);
        if (account is null) return Unauthorized();
        if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword, account.PasswordHash))
            return BadRequest(new { message = "Current password is incorrect." });

        var newHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
        // A concurrent password change must not be overwritten using an old password.
        var changed = await db.Users
            .Where(u => u.Id == account.Id && u.Role == "Customer" && u.PasswordHash == account.PasswordHash)
            .ExecuteUpdateAsync(update => update.SetProperty(u => u.PasswordHash, newHash), ct);
        if (changed == 0)
            return Conflict(new { message = "Your password changed during this request. Please enter your current password again." });

        return Ok(new { message = "Password changed successfully." });
    }

    [HttpPost("photo")]
    [RequestSizeLimit(MaxPhotoSize + 65536)]
    [RequestFormLimits(MultipartBodyLengthLimit = MaxPhotoSize + 65536)]
    public async Task<IActionResult> UploadPhoto(IFormFile file)
    {
        var user = await CurrentCustomer();
        if (user is null) return Unauthorized();
        if (file.Length == 0 || file.Length > MaxPhotoSize)
            return BadRequest(new { message = "Choose an image smaller than 5 MB." });

        await using var input = file.OpenReadStream();
        var header = new byte[12];
        var count = await input.ReadAtLeastAsync(header, header.Length, throwOnEndOfStream: false);
        var extension = count >= 8 && header.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }) ? ".png"
            : count >= 3 && header[0] == 255 && header[1] == 216 && header[2] == 255 ? ".jpg"
            : count == 12 && System.Text.Encoding.ASCII.GetString(header, 0, 4) == "RIFF"
                && System.Text.Encoding.ASCII.GetString(header, 8, 4) == "WEBP" ? ".webp" : null;
        var expectedType = extension == ".jpg" ? "image/jpeg" : extension == ".png" ? "image/png" : "image/webp";
        if (extension is null || !string.Equals(file.ContentType, expectedType, StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { message = "Choose a JPEG, PNG, or WebP image." });

        var directory = Path.Combine(environment.WebRootPath ?? Path.Combine(environment.ContentRootPath, "wwwroot"), "uploads", "customers");
        Directory.CreateDirectory(directory);
        var filename = $"{Guid.NewGuid():N}{extension}";
        var path = Path.Combine(directory, filename);
        try
        {
            await using (var output = new FileStream(path, FileMode.CreateNew))
            {
                await output.WriteAsync(header.AsMemory(0, count));
                await input.CopyToAsync(output);
            }
            user.ProfilePhotoUrl = $"/uploads/customers/{filename}";
            await db.SaveChangesAsync();
        }
        catch
        {
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            throw;
        }
        return Ok(Profile(user));
    }
}
