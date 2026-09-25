using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Customers;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Route("api/studio/customers")]
[Authorize(Roles = "Studio")]
public class StudioCustomersController(ApplicationDbContext context) : ControllerBase
{
    [HttpGet("{customerId:int}")]
    public async Task<ActionResult<StudioCustomerDetailResponse>> GetById(
        int customerId, CancellationToken cancellationToken)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) || userId <= 0)
            return Unauthorized(new { message = "A valid user token is required." });
        if (!await context.Users.AsNoTracking().AnyAsync(
                user => user.Id == userId && user.Role == "Studio", cancellationToken))
            return Forbid();

        // Derive ownership from the JWT. Never load this customer's other bookings.
        var bookings = await context.Bookings.AsNoTracking()
            .Where(booking => booking.CustomerId == customerId && booking.Studio.UserId == userId)
            .OrderByDescending(booking => booking.BookingDate)
            .ThenByDescending(booking => booking.StartTime).ThenByDescending(booking => booking.Id)
            .Select(booking => new
            {
                booking.CustomerId, booking.Customer.FullName, booking.Customer.Email,
                booking.Id,
                PackageName = booking.Package.StudioId == booking.StudioId
                    ? (booking.Package.Name.Trim() == "" ? booking.Package.PackageName : booking.Package.Name)
                    : "",
                booking.BookingDate, booking.Status, booking.TotalPrice, booking.CreatedAt
            }).ToListAsync(cancellationToken);

        if (bookings.Count == 0) return NotFound(new { message = "Customer was not found." });
        var customer = bookings[0];
        return Ok(new StudioCustomerDetailResponse
        {
            CustomerId = customer.CustomerId, Name = customer.FullName, Email = customer.Email,
            TotalBookings = bookings.Count,
            CompletedBookings = bookings.Count(booking => booking.Status == BookingStatus.Completed),
            ActiveBookings = bookings.Count(booking => booking.Status is BookingStatus.Pending
                or BookingStatus.AIRecommended or BookingStatus.AwaitingApproval
                or BookingStatus.Confirmed or BookingStatus.Rescheduled),
            Bookings = bookings.Select(booking => new StudioCustomerBookingResponse
            {
                BookingId = booking.Id, PackageName = booking.PackageName,
                BookingDate = booking.BookingDate, Status = booking.Status.ToString(),
                TotalPrice = booking.TotalPrice, CreatedAt = booking.CreatedAt
            }).ToList()
        });
    }

    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<StudioCustomerResponse>>> GetAll(
        CancellationToken cancellationToken)
    {
        if (!int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) || userId <= 0)
            return Unauthorized(new { message = "A valid user token is required." });

        // Also verify the account's current role in case it changed after JWT issuance.
        if (!await context.Users.AsNoTracking().AnyAsync(
                user => user.Id == userId && user.Role == "Studio", cancellationToken))
            return Forbid();

        // Scope before grouping: counts and latest-booking data cannot include
        // this customer's bookings with other studios. No studio ID is accepted.
        var customers = await context.Bookings.AsNoTracking()
            .Where(booking => booking.Studio.UserId == userId)
            .GroupBy(booking => new
            {
                booking.CustomerId,
                booking.Customer.FullName,
                booking.Customer.Email
            })
            .Select(group => new
            {
                group.Key.CustomerId,
                Name = group.Key.FullName,
                group.Key.Email,
                TotalBookings = group.Count(),
                LatestBookingDate = group.Max(booking => booking.BookingDate),
                LatestBookingStatus = group
                    .OrderByDescending(booking => booking.BookingDate)
                    .ThenByDescending(booking => booking.StartTime)
                    .ThenByDescending(booking => booking.Id)
                    .Select(booking => booking.Status)
                    .First()
            })
            .OrderBy(customer => customer.Name)
            .ThenBy(customer => customer.CustomerId)
            .ToListAsync(cancellationToken);

        // Explicit projection keeps password hashes and other user fields out
        // of both the database result and the API response.
        return Ok(customers.Select(customer => new StudioCustomerResponse
        {
            CustomerId = customer.CustomerId,
            Name = customer.Name,
            Email = customer.Email,
            TotalBookings = customer.TotalBookings,
            LatestBookingDate = customer.LatestBookingDate,
            LatestBookingStatus = customer.LatestBookingStatus.ToString()
        }).ToList());
    }
}
