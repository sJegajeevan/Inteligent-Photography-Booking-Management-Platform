using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Bookings;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BookingsController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public BookingsController(ApplicationDbContext context)
    {
        _context = context;
    }

    // GET: /api/bookings
    [HttpGet]
    public async Task<ActionResult<IEnumerable<BookingResponse>>> GetBookings()
    {
        var bookings = await _context.Bookings
            .AsNoTracking()
            .OrderByDescending(booking => booking.BookingDate)
            .ThenByDescending(booking => booking.StartTime)
            .ToListAsync();

        return Ok(bookings.Select(ToResponse));
    }

    // GET: /api/bookings/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<BookingResponse>> GetBooking(int id)
    {
        var booking = await _context.Bookings
            .AsNoTracking()
            .FirstOrDefaultAsync(booking => booking.Id == id);

        if (booking is null)
        {
            return NotFound(new { message = "Booking not found." });
        }

        return Ok(ToResponse(booking));
    }

    // POST: /api/bookings
    [HttpPost]
    public async Task<ActionResult<BookingResponse>> CreateBooking(CreateBookingRequest request)
    {
        var today = DateOnly.FromDateTime(DateTime.Today);

        if (request.BookingDate < today)
        {
            return BadRequest(new { message = "Booking date cannot be in the past." });
        }

        if (request.StartTime >= request.EndTime)
        {
            return BadRequest(new { message = "Start time must be before end time." });
        }

        if (request.TotalPrice <= 0)
        {
            return BadRequest(new { message = "Total price must be greater than zero." });
        }

        var booking = new Booking
        {
            CustomerId = request.CustomerId,
            StudioId = request.StudioId,
            PackageId = request.PackageId,
            BookingDate = request.BookingDate,
            StartTime = request.StartTime,
            EndTime = request.EndTime,
            Location = request.Location,
            Notes = request.Notes,
            TotalPrice = request.TotalPrice,
            Status = BookingStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };

        _context.Bookings.Add(booking);
        await _context.SaveChangesAsync();

        return CreatedAtAction(nameof(GetBooking), new { id = booking.Id }, ToResponse(booking));
    }

    // PATCH: /api/bookings/5/status
    [HttpPatch("{id:int}/status")]
    public async Task<ActionResult<BookingResponse>> UpdateBookingStatus(
        int id,
        UpdateBookingStatusRequest request)
    {
        var booking = await _context.Bookings.FindAsync(id);

        if (booking is null)
        {
            return NotFound(new { message = "Booking not found." });
        }

        if (booking.Status == request.NewStatus)
        {
            return BadRequest(new { message = "Booking already has this status." });
        }

        if (!IsValidStatusTransition(booking.Status, request.NewStatus))
        {
            return BadRequest(new
            {
                message = $"Cannot change booking status from {booking.Status} to {request.NewStatus}."
            });
        }

        var oldStatus = booking.Status;
        booking.Status = request.NewStatus;
        booking.UpdatedAt = DateTime.UtcNow;

        RecordStatusChange(booking.Id, oldStatus, request.NewStatus, request.ChangedBy, request.Reason);

        await _context.SaveChangesAsync();

        return Ok(ToResponse(booking));
    }

    // GET: /api/bookings/5/history
    [HttpGet("{id:int}/history")]
    public async Task<ActionResult<IEnumerable<BookingStatusHistoryResponse>>> GetBookingHistory(int id)
    {
        var bookingExists = await _context.Bookings.AnyAsync(booking => booking.Id == id);

        if (!bookingExists)
        {
            return NotFound(new { message = "Booking not found." });
        }

        var history = await _context.BookingStatusHistories
            .AsNoTracking()
            .Where(item => item.BookingId == id)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync();

        return Ok(history.Select(ToHistoryResponse));
    }

    // POST: /api/bookings/5/cancel
    [HttpPost("{id:int}/cancel")]
    public async Task<ActionResult<BookingResponse>> CancelBooking(int id, CancelBookingRequest request)
    {
        var booking = await _context.Bookings.FindAsync(id);

        if (booking is null)
        {
            return NotFound(new { message = "Booking not found." });
        }

        if (!IsValidStatusTransition(booking.Status, BookingStatus.Cancelled))
        {
            return BadRequest(new { message = $"A {booking.Status} booking cannot be cancelled." });
        }

        var oldStatus = booking.Status;
        booking.Status = BookingStatus.Cancelled;
        booking.UpdatedAt = DateTime.UtcNow;

        RecordStatusChange(booking.Id, oldStatus, BookingStatus.Cancelled, request.ChangedBy, request.Reason);

        await _context.SaveChangesAsync();

        return Ok(ToResponse(booking));
    }

    private static bool IsValidStatusTransition(BookingStatus currentStatus, BookingStatus newStatus)
    {
        return currentStatus switch
        {
            BookingStatus.Pending => newStatus is BookingStatus.AIRecommended
                or BookingStatus.AwaitingApproval
                or BookingStatus.Confirmed
                or BookingStatus.Rejected
                or BookingStatus.Cancelled,
            BookingStatus.AIRecommended => newStatus is BookingStatus.AwaitingApproval
                or BookingStatus.Confirmed
                or BookingStatus.Rejected
                or BookingStatus.Cancelled,
            BookingStatus.AwaitingApproval => newStatus is BookingStatus.Confirmed
                or BookingStatus.Rejected
                or BookingStatus.Cancelled,
            BookingStatus.Confirmed => newStatus is BookingStatus.Rescheduled
                or BookingStatus.Cancelled
                or BookingStatus.Completed,
            BookingStatus.Rescheduled => newStatus is BookingStatus.AwaitingApproval
                or BookingStatus.Confirmed
                or BookingStatus.Cancelled,
            _ => false
        };
    }

    private void RecordStatusChange(
        int bookingId,
        BookingStatus oldStatus,
        BookingStatus newStatus,
        string changedBy,
        string? reason)
    {
        _context.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = bookingId,
            OldStatus = oldStatus,
            NewStatus = newStatus,
            ChangedBy = changedBy,
            Reason = reason,
            CreatedAt = DateTime.UtcNow
        });
    }

    private static BookingStatusHistoryResponse ToHistoryResponse(BookingStatusHistory history)
    {
        return new BookingStatusHistoryResponse
        {
            Id = history.Id,
            BookingId = history.BookingId,
            OldStatus = history.OldStatus,
            NewStatus = history.NewStatus,
            ChangedBy = history.ChangedBy,
            Reason = history.Reason,
            CreatedAt = history.CreatedAt
        };
    }

    private static BookingResponse ToResponse(Booking booking)
    {
        return new BookingResponse
        {
            Id = booking.Id,
            CustomerId = booking.CustomerId,
            StudioId = booking.StudioId,
            PackageId = booking.PackageId,
            BookingDate = booking.BookingDate,
            StartTime = booking.StartTime,
            EndTime = booking.EndTime,
            Location = booking.Location,
            Notes = booking.Notes,
            Status = booking.Status,
            TotalPrice = booking.TotalPrice,
            CreatedAt = booking.CreatedAt,
            UpdatedAt = booking.UpdatedAt
        };
    }
}
