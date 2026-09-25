using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Bookings;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyPackageService = PhotographyBooking.Api.Services.PhotographyPackageService;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "Customer,Studio")]
public class BookingsController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly PackagePriceCalculationService _priceCalculator;

    private readonly BookingSlotValidationService _slots;
    private readonly PhotographyPackageService _packages;

    public BookingsController(ApplicationDbContext context, PackagePriceCalculationService priceCalculator,
        BookingSlotValidationService slots, PhotographyPackageService packages)
    {
        _context = context;
        _priceCalculator = priceCalculator;
        _slots = slots;
        _packages = packages;
    }

    // GET: /api/bookings
    [HttpGet]
    public async Task<ActionResult<IEnumerable<BookingResponse>>> GetBookings()
    {
        var actor = await GetActor();
        if (actor is null) return Forbid();
        var bookings = await OwnedBookings(actor)
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
        var actor = await GetActor();
        if (actor is null) return Forbid();
        var booking = await OwnedBookings(actor)
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
    [Authorize(Roles = "Customer")]
    public async Task<ActionResult<BookingResponse>> CreateBooking(CreateBookingRequest request)
    {
        var actor = await GetActor();
        if (actor is null || actor.Role != "Customer") return Forbid();
        var today = DateOnly.FromDateTime(DateTime.Today);

        var timeError = BookingSlotRules.ValidateTime(request.BookingDate, request.StartTime, request.EndTime, today);
        if (timeError is not null) return BadRequest(new { message = timeError });

        // Serialize creation per studio across API instances. ReadCommitted gives
        // the overlap query a fresh snapshot after a waiting request gets the lock.
        await using var transaction = await _context.Database.BeginTransactionAsync(
            System.Data.IsolationLevel.ReadCommitted);
        var studios = await _context.Studios.FromSqlInterpolated(
            $"SELECT * FROM \"Studios\" WHERE \"Id\" = {request.StudioId} FOR UPDATE")
            .AsNoTracking().ToListAsync();
        if (studios.Count == 0)
        {
            return BadRequest(new { message = "The selected studio does not exist." });
        }

        // Hold this row against availability edits/deletion until creation commits.
        // No slot ID is supplied by the API: the existing unique studio/date key
        // identifies the availability belonging to this studio.
        var slots = await _context.StudioAvailabilities.FromSqlInterpolated(
            $"SELECT * FROM \"StudioAvailabilities\" WHERE \"StudioId\" = {request.StudioId} AND \"Date\" = {request.BookingDate} FOR SHARE")
            .AsNoTracking().ToListAsync();
        var slot = slots.SingleOrDefault();
        var slotResult = await _slots.CheckAvailabilityAndConflictsAsync(request.StudioId, request.BookingDate,
            request.StartTime, request.EndTime, slot, actor.Id, HttpContext.RequestAborted);
        if (!slotResult.IsAvailable) return Conflict(new { message = slotResult.Error });

        var selectedPackage = await _packages.GetPublicAsync(request.StudioId, request.PackageId);
        if (selectedPackage is null)
        {
            return BadRequest(new { message = "Select an active package belonging to this studio." });
        }

        // Purchased extra hours extend the package's allowed coverage.
        if (!BookingSlotRules.FitsPackageDuration(selectedPackage.DurationHours, request.ExtraHours, request.StartTime, request.EndTime))
            return BadRequest(new { message = "The booking must fit within the package duration plus purchased extra hours." });

        var pricing = await _priceCalculator.CalculatePublicAsync(request.StudioId, request.PackageId,
            new PackagePriceCalculationRequestDto
            {
                SelectedAddonIds = request.SelectedAddonIds,
                ExtraHours = request.ExtraHours,
                AdditionalPhotographers = request.AdditionalPhotographers
            });
        if (pricing.Result is null)
            return BadRequest(new { message = pricing.Error ?? "Unable to calculate the package price." });
        var priceError = BookingSlotRules.ValidateBookingTotal(pricing.Result.FinalPrice);
        if (priceError is not null) return BadRequest(new { message = priceError });

        var booking = new Booking
        {
            CustomerId = actor.Id,
            StudioId = request.StudioId,
            PackageId = request.PackageId,
            BookingDate = request.BookingDate,
            StartTime = request.StartTime,
            EndTime = request.EndTime,
            Location = request.Location,
            Notes = request.Notes,
            TotalPrice = pricing.Result.FinalPrice,
            PricingSnapshotJson = JsonSerializer.Serialize(pricing.Result),
            Status = BookingStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };

        // Publish the notification only when the entire booking transaction commits.
        _context.Bookings.Add(booking);
        await _context.SaveChangesAsync();
        RecordStatusChange(booking.Id, null, BookingStatus.Pending, $"{actor.Role} #{actor.Id}", null);
        _context.Notifications.Add(new Notification
        {
            CustomerId = booking.CustomerId,
            BookingId = booking.Id,
            Title = "Booking created",
            Message = $"Your booking #{booking.Id} has been created and is pending confirmation.",
            Type = "BookingCreated"
        });
        await _context.SaveChangesAsync();
        await transaction.CommitAsync();

        return CreatedAtAction(nameof(GetBooking), new { id = booking.Id }, ToResponse(booking));
    }

    // PATCH: /api/bookings/5/status
    [HttpPatch("{id:int}/status")]
    [Authorize(Roles = "Studio")]
    public async Task<ActionResult<BookingResponse>> UpdateBookingStatus(
        int id,
        UpdateBookingStatusRequest request)
    {
        var actor = await GetActor();
        if (actor is null || actor.Role != "Studio") return Forbid();
        var booking = await OwnedBookings(actor).AsNoTracking().SingleOrDefaultAsync(item => item.Id == id);

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

        if (!await ApplyStatusChange(booking, actor, request.NewStatus, request.Reason))
            return Conflict(new { message = "Booking status changed. Reload the booking and try again." });

        return Ok(ToResponse(booking));
    }

    // GET: /api/bookings/5/history
    [HttpGet("{id:int}/history")]
    public async Task<ActionResult<IEnumerable<BookingStatusHistoryResponse>>> GetBookingHistory(int id)
    {
        var actor = await GetActor();
        if (actor is null) return Forbid();
        var bookingExists = await OwnedBookings(actor).AnyAsync(booking => booking.Id == id);

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
        var actor = await GetActor();
        if (actor is null) return Forbid();
        var booking = await OwnedBookings(actor).AsNoTracking().SingleOrDefaultAsync(item => item.Id == id);

        if (booking is null)
        {
            return NotFound(new { message = "Booking not found." });
        }

        if (!IsValidStatusTransition(booking.Status, BookingStatus.Cancelled))
        {
            return BadRequest(new { message = $"A {booking.Status} booking cannot be cancelled." });
        }

        if (!await ApplyStatusChange(booking, actor, BookingStatus.Cancelled, request.Reason))
            return Conflict(new { message = "Booking status changed. Reload the booking and try again." });

        return Ok(ToResponse(booking));
    }

    private async Task<User?> GetActor()
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) || userId <= 0)
            return null;
        var actor = await _context.Users.AsNoTracking().SingleOrDefaultAsync(user => user.Id == userId);
        return actor is not null && (actor.Role == "Customer" || actor.Role == "Studio") && User.IsInRole(actor.Role)
            ? actor : null;
    }

    private IQueryable<Booking> OwnedBookings(User actor) => actor.Role == "Customer"
        ? _context.Bookings.Where(booking => booking.CustomerId == actor.Id)
        : _context.Bookings.Where(booking => booking.Studio.UserId == actor.Id);

    private async Task<bool> ApplyStatusChange(Booking booking, User actor, BookingStatus newStatus, string? reason)
    {
        // Compare-and-update prevents concurrent requests from bypassing the
        // transition rules. History, status and notification commit together.
        await using var transaction = await _context.Database.BeginTransactionAsync();
        var oldStatus = booking.Status;
        var changedAt = DateTime.UtcNow;
        var changed = await OwnedBookings(actor)
            .Where(item => item.Id == booking.Id && item.Status == oldStatus)
            .ExecuteUpdateAsync(update => update
                .SetProperty(item => item.Status, newStatus)
                .SetProperty(item => item.UpdatedAt, changedAt));
        if (changed == 0) return false;
        RecordStatusChange(booking.Id, oldStatus, newStatus, $"{actor.Role} #{actor.Id}", reason);
        _context.Notifications.Add(new Notification
        {
            CustomerId = booking.CustomerId,
            BookingId = booking.Id,
            Title = newStatus == BookingStatus.Cancelled ? "Booking cancelled"
                : newStatus == BookingStatus.Confirmed ? "Booking confirmed" : "Booking status changed",
            Message = $"Your booking #{booking.Id} changed from {StatusLabel(oldStatus)} to {StatusLabel(newStatus)}.",
            Type = newStatus == BookingStatus.Cancelled ? "BookingCancelled"
                : newStatus == BookingStatus.Confirmed ? "BookingConfirmed" : "BookingStatusChanged",
            CreatedAt = changedAt
        });
        await _context.SaveChangesAsync();
        await transaction.CommitAsync();
        booking.Status = newStatus;
        booking.UpdatedAt = changedAt;
        return true;
    }

    private static string StatusLabel(BookingStatus status) => status switch
    {
        BookingStatus.AwaitingApproval => "Awaiting approval",
        BookingStatus.AIRecommended => "AI recommended",
        _ => status.ToString()
    };

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
        BookingStatus? oldStatus,
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
            Customization = booking.PricingSnapshotJson is null
                ? null
                : JsonSerializer.Deserialize<PackagePriceCalculationResponseDto>(booking.PricingSnapshotJson),
            CreatedAt = booking.CreatedAt,
            UpdatedAt = booking.UpdatedAt
        };
    }
}
