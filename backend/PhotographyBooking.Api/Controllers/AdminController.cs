using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Admin;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin")]
[Route("api/admin")]
public class AdminController(ApplicationDbContext db) : ControllerBase
{
    [HttpGet("dashboard")]
    public async Task<ActionResult<AdminDashboardResponse>> Dashboard(CancellationToken ct)
    {
        var statuses = await db.Bookings.AsNoTracking().GroupBy(item => item.Status).Select(group => new AdminStatusCount(group.Key.ToString(), group.Count())).OrderBy(item => item.Status).ToListAsync(ct);
        var recentBookings = await BookingSummaries().OrderByDescending(item => item.CreatedAt).Take(8).ToListAsync(ct);
        var recentStudios = await StudioSummaries().OrderByDescending(item => item.CreatedAt).Take(6).ToListAsync(ct);
        return Ok(new AdminDashboardResponse(
            await db.Studios.CountAsync(ct),
            await db.Users.CountAsync(item => item.Role == "Customer", ct),
            await db.Bookings.CountAsync(ct),
            await db.PhotographyPackages.CountAsync(ct),
            await db.Reviews.CountAsync(ct),
            statuses, recentBookings, recentStudios));
    }

    [HttpGet("studios")]
    public async Task<ActionResult<IReadOnlyList<AdminStudioSummary>>> Studios([FromQuery] string? search, CancellationToken ct)
    {
        var query = StudioSummaries();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var value = search.Trim().ToLower();
            query = query.Where(item => item.StudioName.ToLower().Contains(value) || item.OwnerName.ToLower().Contains(value) || item.Location.ToLower().Contains(value) || item.Email.ToLower().Contains(value));
        }
        return Ok(await query.OrderBy(item => item.StudioName).ToListAsync(ct));
    }

    [HttpGet("studios/{id:guid}")]
    public async Task<ActionResult<AdminStudioDetail>> Studio(Guid id, CancellationToken ct)
    {
        var studio = await db.Studios.AsNoTracking().Where(item => item.Id == id).Select(item => new AdminStudioDetail(
            item.Id, item.StudioName, item.User.FullName, item.User.Email, item.Location, item.Address, item.ContactNumber, item.Email,
            item.ExperienceYears, item.PhotographyTypes, item.StartingPrice, item.LogoUrl, item.CoverPhotoUrl, null,
            db.StudioPortfolios.Count(portfolio => portfolio.StudioId == item.Id),
            db.StudioServices.Count(service => service.StudioId == item.Id),
            db.PhotographyPackages.Count(package => package.StudioId == item.Id),
            db.StudioAvailabilities.Count(availability => availability.StudioId == item.Id),
            db.Bookings.Count(booking => booking.StudioId == item.Id),
            db.Reviews.Where(review => review.StudioId == item.Id).Select(review => (double?)review.Rating).Average(),
            db.StudioServices.Where(service => service.StudioId == item.Id).OrderBy(service => service.ServiceName).Select(service => new AdminNamedItem(service.Id, service.ServiceName, null, service.StartingPrice, null)).ToList(),
            db.PhotographyPackages.Where(package => package.StudioId == item.Id).OrderBy(package => package.Name).Select(package => new AdminNamedItem(package.Id, package.Name, package.Category, package.Price, package.Status.ToString())).ToList()
        )).SingleOrDefaultAsync(ct);
        return studio is null ? NotFound(new { message = "Studio not found." }) : Ok(studio);
    }

    [HttpGet("customers")]
    public async Task<ActionResult<IReadOnlyList<AdminCustomerSummary>>> Customers([FromQuery] string? search, CancellationToken ct)
    {
        var query = db.Users.AsNoTracking().Where(item => item.Role == "Customer").Select(item => new AdminCustomerSummary(
            item.Id, item.FullName, item.Email, item.CreatedAt,
            db.Bookings.Count(booking => booking.CustomerId == item.Id),
            db.Reviews.Count(review => review.CustomerId == item.Id)));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var value = search.Trim().ToLower();
            query = query.Where(item => item.FullName.ToLower().Contains(value) || item.Email.ToLower().Contains(value));
        }
        return Ok(await query.OrderBy(item => item.FullName).ToListAsync(ct));
    }

    [HttpGet("customers/{id:int}")]
    public async Task<ActionResult<AdminCustomerDetail>> Customer(int id, CancellationToken ct)
    {
        var customer = await db.Users.AsNoTracking().Where(item => item.Id == id && item.Role == "Customer")
            .Select(item => new { item.Id, item.FullName, item.Email, item.PhoneNumber, item.ProfilePhotoUrl, item.CreatedAt })
            .SingleOrDefaultAsync(ct);
        if (customer is null) return NotFound(new { message = "Customer not found." });
        var bookings = await BookingSummaries().Where(item => db.Bookings.Any(source => source.Id == item.Id && source.CustomerId == id)).OrderByDescending(item => item.CreatedAt).ToListAsync(ct);
        var reviews = await db.Reviews.AsNoTracking().Where(review => review.CustomerId == id).OrderByDescending(review => review.CreatedAt)
            .Select(review => new AdminReviewSummary(review.Id, review.Customer.FullName, review.Studio.StudioName, review.Rating, review.Comment, review.CreatedAt)).ToListAsync(ct);
        return Ok(new AdminCustomerDetail(customer.Id, customer.FullName, customer.Email, customer.PhoneNumber, customer.ProfilePhotoUrl, customer.CreatedAt, bookings, reviews));
    }

    [HttpGet("bookings")]
    public async Task<ActionResult<IReadOnlyList<AdminBookingSummary>>> Bookings([FromQuery] string? search, [FromQuery] BookingStatus? status, CancellationToken ct)
    {
        var query = BookingSummaries();
        if (status.HasValue) query = query.Where(item => item.Status == status.Value.ToString());
        if (!string.IsNullOrWhiteSpace(search))
        {
            var value = search.Trim().ToLower();
            query = query.Where(item => item.CustomerName.ToLower().Contains(value) || item.StudioName.ToLower().Contains(value) || item.PackageName.ToLower().Contains(value) || item.Id.ToString().Contains(value));
        }
        return Ok(await query.OrderByDescending(item => item.CreatedAt).ToListAsync(ct));
    }

    [HttpGet("bookings/{id:int}")]
    public async Task<ActionResult<AdminBookingDetail>> Booking(int id, CancellationToken ct)
    {
        var booking = await db.Bookings.AsNoTracking().Where(item => item.Id == id).Select(item => new AdminBookingDetail(
            item.Id, item.Customer.FullName, item.Customer.Email, item.Studio.StudioName, item.Package.Name, item.BookingDate, item.StartTime, item.EndTime,
            item.Location, item.Notes, item.TotalPrice, item.Status.ToString(), item.PricingSnapshotJson, item.CreatedAt,
            item.BookingLocation == null ? null : new AdminBookingLocation(item.BookingLocation.Address, item.BookingLocation.City, item.BookingLocation.Latitude, item.BookingLocation.Longitude, item.BookingLocation.Notes),
            item.StatusHistory.OrderBy(history => history.CreatedAt).Select(history => new AdminStatusHistory(history.OldStatus.HasValue ? history.OldStatus.Value.ToString() : null, history.NewStatus.ToString(), history.ChangedBy, history.Reason, history.CreatedAt)).ToList()
        )).SingleOrDefaultAsync(ct);
        return booking is null ? NotFound(new { message = "Booking not found." }) : Ok(booking);
    }

    [HttpGet("reviews")]
    public async Task<ActionResult<IReadOnlyList<AdminReviewSummary>>> Reviews([FromQuery] string? search, [FromQuery] int? rating, CancellationToken ct)
    {
        var query = db.Reviews.AsNoTracking().Select(review => new AdminReviewSummary(review.Id, review.Customer.FullName, review.Studio.StudioName, review.Rating, review.Comment, review.CreatedAt));
        if (rating is >= 1 and <= 5) query = query.Where(item => item.Rating == rating.Value);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var value = search.Trim().ToLower();
            query = query.Where(item => item.CustomerName.ToLower().Contains(value) || item.StudioName.ToLower().Contains(value) || (item.Comment ?? "").ToLower().Contains(value));
        }
        return Ok(await query.OrderByDescending(item => item.CreatedAt).ToListAsync(ct));
    }

    [HttpGet("reports")]
    public async Task<ActionResult<AdminReportsResponse>> Reports(CancellationToken ct)
    {
        var statuses = await db.Bookings.AsNoTracking().GroupBy(item => item.Status).Select(group => new AdminStatusCount(group.Key.ToString(), group.Count())).OrderBy(item => item.Status).ToListAsync(ct);
        var byStudio = await db.Bookings.AsNoTracking().GroupBy(item => item.Studio.StudioName).Select(group => new AdminCountByName(group.Key, group.Count())).OrderByDescending(item => item.Count).Take(10).ToListAsync(ct);
        var packages = await db.Bookings.AsNoTracking().GroupBy(item => item.Package.Name).Select(group => new AdminCountByName(group.Key, group.Count())).OrderByDescending(item => item.Count).Take(10).ToListAsync(ct);
        return Ok(new AdminReportsResponse(statuses, byStudio, packages,
            await db.Reviews.Select(review => (double?)review.Rating).AverageAsync(ct),
            await db.Reviews.CountAsync(ct), await db.Bookings.CountAsync(ct), await db.Studios.CountAsync(ct), await db.Users.CountAsync(item => item.Role == "Customer", ct)));
    }

    private IQueryable<AdminStudioSummary> StudioSummaries() => db.Studios.AsNoTracking().Select(item => new AdminStudioSummary(item.Id, item.StudioName, item.User.FullName, item.Location, item.Email, item.ContactNumber, null));

    private IQueryable<AdminBookingSummary> BookingSummaries() => db.Bookings.AsNoTracking().Select(item => new AdminBookingSummary(item.Id, item.Customer.FullName, item.Studio.StudioName, item.Package.Name, item.BookingDate, item.TotalPrice, item.Status.ToString(), item.CreatedAt));
}
