using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.DTOs.BookingMessages;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

public partial class BookingsController
{
    [HttpGet("{bookingId:int}/messages")]
    public async Task<ActionResult<IEnumerable<BookingMessageResponse>>> GetMessages(int bookingId)
    {
        var actor = await GetActor();
        if (actor is null) return Forbid();
        if (!await OwnedBookings(actor).AnyAsync(b => b.Id == bookingId))
            return NotFound(new { message = "Booking not found." });

        return Ok(await _context.BookingMessages.AsNoTracking()
            .Where(m => m.BookingId == bookingId)
            .OrderBy(m => m.SentAt).ThenBy(m => m.Id)
            .Select(m => new BookingMessageResponse(m.Id, m.BookingId, m.SenderUserId,
                m.SenderUser.FullName, m.SenderUser.Role, m.Message, m.SentAt))
            .ToListAsync());
    }

    [HttpPost("{bookingId:int}/messages")]
    public async Task<ActionResult<BookingMessageResponse>> SendMessage(int bookingId, SendBookingMessageRequest request)
    {
        var actor = await GetActor();
        if (actor is null) return Forbid();
        if (!await OwnedBookings(actor).AnyAsync(b => b.Id == bookingId))
            return NotFound(new { message = "Booking not found." });
        var text = request.Message?.Trim();
        if (string.IsNullOrEmpty(text) || request.Message!.Length > 1000)
            return BadRequest(new { message = "Message must contain between 1 and 1000 characters." });

        var message = new BookingMessage { BookingId = bookingId, SenderUserId = actor.Id,
            Message = text, SentAt = _clock.GetUtcNow().UtcDateTime };
        _context.BookingMessages.Add(message);
        await _context.SaveChangesAsync();
        return CreatedAtAction(nameof(GetMessages), new { bookingId },
            new BookingMessageResponse(message.Id, bookingId, actor.Id, actor.FullName,
                actor.Role, message.Message, message.SentAt));
    }

    [HttpGet("conversations")]
    [Authorize(Roles = "Studio")]
    public async Task<ActionResult<IEnumerable<BookingConversationResponse>>> GetConversations()
    {
        var actor = await GetActor();
        if (actor is null || actor.Role != "Studio") return Forbid();
        // Include bookings without messages so the studio can initiate a conversation.
        var conversations = await OwnedBookings(actor).AsNoTracking()
            .Select(b => new BookingConversationResponse(b.Id, b.Customer.FullName,
                b.Package.Name, b.BookingDate,
                _context.BookingMessages.Where(m => m.BookingId == b.Id)
                    .OrderByDescending(m => m.SentAt).ThenByDescending(m => m.Id)
                    .Select(m => m.Message).FirstOrDefault(),
                _context.BookingMessages.Where(m => m.BookingId == b.Id)
                    .OrderByDescending(m => m.SentAt).ThenByDescending(m => m.Id)
                    .Select(m => (DateTime?)m.SentAt).FirstOrDefault()))
            .ToListAsync();
        return Ok(conversations.OrderByDescending(c => c.LatestMessageTime)
            .ThenByDescending(c => c.BookingDate).ThenByDescending(c => c.BookingId));
    }
}
