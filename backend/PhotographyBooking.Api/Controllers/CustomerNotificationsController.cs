using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Customers;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Authorize(Roles = "Customer")]
[Route("api/customer/notifications")]
public class CustomerNotificationsController(ApplicationDbContext db) : ControllerBase
{
    private async Task<int?> CustomerId(CancellationToken ct)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) || id <= 0)
            return null;
        return await db.Users.AnyAsync(u => u.Id == id && u.Role == "Customer", ct) ? id : null;
    }

    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        var customerId = await CustomerId(ct);
        if (customerId is null) return Unauthorized();
        return Ok(await db.Notifications.AsNoTracking()
            .Where(n => n.CustomerId == customerId.Value)
            .OrderByDescending(n => n.CreatedAt).ThenByDescending(n => n.Id)
            .Select(n => new NotificationResponse(n.Id, n.Title, n.Message, n.Type,
                n.BookingId, n.IsRead, n.CreatedAt)).ToListAsync(ct));
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount(CancellationToken ct)
    {
        var customerId = await CustomerId(ct);
        if (customerId is null) return Unauthorized();
        return Ok(new { unreadCount = await db.Notifications.CountAsync(
            n => n.CustomerId == customerId.Value && !n.IsRead, ct) });
    }

    [HttpPatch("{id:guid}/read")]
    public async Task<IActionResult> MarkRead(Guid id, CancellationToken ct)
    {
        var customerId = await CustomerId(ct);
        if (customerId is null) return Unauthorized();
        // Include ownership in the UPDATE itself; repeated reads are idempotent.
        var changed = await db.Notifications
            .Where(n => n.Id == id && n.CustomerId == customerId.Value)
            .ExecuteUpdateAsync(update => update.SetProperty(n => n.IsRead, true), ct);
        return changed == 0 ? NotFound(new { message = "Notification not found." }) : NoContent();
    }
}
