using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Authorize(Roles = "Studio")]
[Route("api/studio/notifications")]
public class StudioNotificationsController(ApplicationDbContext db) : ControllerBase
{
    private async Task<int?> StudioUserId(CancellationToken ct)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) || id <= 0)
            return null;
        return await db.Users.AnyAsync(u => u.Id == id && u.Role == "Studio", ct) ? id : null;
    }

    private IQueryable<Notification> OwnedNotifications(int userId) => db.Notifications
        .Where(n => n.StudioId != null && n.Studio!.UserId == userId);

    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        var userId = await StudioUserId(ct);
        if (userId is null) return Unauthorized();
        return Ok(await OwnedNotifications(userId.Value).AsNoTracking()
            .OrderByDescending(n => n.CreatedAt).ThenByDescending(n => n.Id)
            .Select(n => new { n.Id, CustomerName = n.Customer.FullName, n.Title,
                n.Message, n.Type, n.BookingId, n.IsRead, n.CreatedAt }).ToListAsync(ct));
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount(CancellationToken ct)
    {
        var userId = await StudioUserId(ct);
        if (userId is null) return Unauthorized();
        return Ok(new { unreadCount = await OwnedNotifications(userId.Value).CountAsync(n => !n.IsRead, ct) });
    }

    [HttpPatch("{id:guid}/read")]
    public async Task<IActionResult> MarkRead(Guid id, CancellationToken ct)
    {
        var userId = await StudioUserId(ct);
        if (userId is null) return Unauthorized();
        var changed = await OwnedNotifications(userId.Value).Where(n => n.Id == id)
            .ExecuteUpdateAsync(update => update.SetProperty(n => n.IsRead, true), ct);
        return changed == 0 ? NotFound(new { message = "Notification not found." }) : NoContent();
    }
}
