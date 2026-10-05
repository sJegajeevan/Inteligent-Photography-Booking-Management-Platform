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
        var statuses = await StatusCountsAsync(ct);
        var recentBookings = await BookingSummaries(db.Bookings.AsNoTracking().OrderByDescending(item => item.CreatedAt).ThenByDescending(item => item.Id).Take(8)).ToListAsync(ct);
        var recentStudios = await StudioSummaries(db.Studios.AsNoTracking().OrderBy(item => item.StudioName).ThenBy(item => item.Id).Take(6)).ToListAsync(ct);
        return Ok(new AdminDashboardResponse(
            await db.Studios.CountAsync(ct),
            await db.Users.CountAsync(item => item.Role == "Customer", ct),
            await db.Bookings.CountAsync(ct),
            await db.PhotographyPackages.CountAsync(ct),
            await db.Reviews.CountAsync(ct),
            statuses, recentBookings, recentStudios));
    }

    [HttpGet("studios")]
    public async Task<ActionResult<AdminPage<AdminStudioSummary>>> Studios([FromQuery] AdminCollectionQuery request, CancellationToken ct)
    {
        var query = db.Studios.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            var value = request.Search.Trim().ToLower();
            query = query.Where(item => item.StudioName.ToLower().Contains(value) || item.User.FullName.ToLower().Contains(value) || item.Location.ToLower().Contains(value) || item.Email.ToLower().Contains(value));
        }
        return Ok(await PageAsync(StudioSummaries(query.OrderBy(item => item.StudioName).ThenBy(item => item.Id)), request, ct));
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
            db.Reviews.Count(review => review.StudioId == item.Id),
            db.Reviews.Where(review => review.StudioId == item.Id).Select(review => (double?)review.Rating).Average(),
            db.StudioServices.Where(service => service.StudioId == item.Id).OrderBy(service => service.ServiceName).Select(service => new AdminNamedItem(service.Id, service.ServiceName, null, service.StartingPrice, null)).ToList(),
            db.PhotographyPackages.Where(package => package.StudioId == item.Id).OrderBy(package => package.Name).Select(package => new AdminNamedItem(
                package.Id, package.Name, package.Category, package.Price,
                package.Status == PhotographyPackageStatus.Active ? "Active" : "Inactive")).ToList()
        )).SingleOrDefaultAsync(ct);
        return studio is null ? NotFound(new { message = "Studio not found." }) : Ok(studio);
    }

    [HttpGet("customers")]
    public async Task<ActionResult<AdminPage<AdminCustomerSummary>>> Customers([FromQuery] AdminCollectionQuery request, CancellationToken ct)
    {
        var query = db.Users.AsNoTracking().Where(item => item.Role == "Customer");
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            var value = request.Search.Trim().ToLower();
            query = query.Where(item => item.FullName.ToLower().Contains(value) || item.Email.ToLower().Contains(value));
        }
        return Ok(await PageAsync(query.OrderBy(item => item.FullName).ThenBy(item => item.Id).Select(item => new AdminCustomerSummary(
            item.Id, item.FullName, item.Email, item.CreatedAt,
            db.Bookings.Count(booking => booking.CustomerId == item.Id), db.Reviews.Count(review => review.CustomerId == item.Id))), request, ct));
    }

    [HttpGet("customers/{id:int}")]
    public async Task<ActionResult<AdminCustomerDetail>> Customer(int id, CancellationToken ct)
    {
        var customer = await db.Users.AsNoTracking().Where(item => item.Id == id && item.Role == "Customer")
            .Select(item => new { item.Id, item.FullName, item.Email, item.PhoneNumber, item.ProfilePhotoUrl, item.CreatedAt })
            .SingleOrDefaultAsync(ct);
        if (customer is null) return NotFound(new { message = "Customer not found." });
        var bookings = await BookingSummaries(db.Bookings.AsNoTracking().Where(item => item.CustomerId == id).OrderByDescending(item => item.CreatedAt).ThenByDescending(item => item.Id)).ToListAsync(ct);
        var reviews = await db.Reviews.AsNoTracking().Where(review => review.CustomerId == id).OrderByDescending(review => review.CreatedAt)
            .Select(review => new AdminReviewSummary(review.Id, review.Customer.FullName, review.Studio.StudioName, review.Rating, review.Comment, review.CreatedAt)).ToListAsync(ct);
        return Ok(new AdminCustomerDetail(customer.Id, customer.FullName, customer.Email, customer.PhoneNumber, customer.ProfilePhotoUrl, customer.CreatedAt, bookings, reviews));
    }

    [HttpGet("bookings")]
    public async Task<ActionResult<AdminPage<AdminBookingSummary>>> Bookings([FromQuery] AdminBookingQuery request, CancellationToken ct)
    {
        var source = FilterBookings(db.Bookings.AsNoTracking(), request)
            .OrderByDescending(item => item.BookingDate).ThenByDescending(item => item.Id);
        return Ok(await PageAsync(BookingSummaries(source), request, ct));
    }

    internal static IQueryable<Booking> FilterBookings(IQueryable<Booking> query, AdminBookingQuery request)
    {
        if (request.Status.HasValue) query = query.Where(item => item.Status == request.Status.Value);
        if (request.StudioId.HasValue) query = query.Where(item => item.StudioId == request.StudioId.Value);
        if (request.CustomerId.HasValue) query = query.Where(item => item.CustomerId == request.CustomerId.Value);
        if (request.FromDate.HasValue) query = query.Where(item => item.BookingDate >= request.FromDate.Value);
        if (request.ToDate.HasValue) query = query.Where(item => item.BookingDate <= request.ToDate.Value);
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            var value = request.Search.Trim().ToLower();
            query = query.Where(item => item.Customer.FullName.ToLower().Contains(value) ||
                item.Studio.StudioName.ToLower().Contains(value) || item.Package.Name.ToLower().Contains(value) || item.Id.ToString().Contains(value));
        }
        return query;
    }

    [HttpGet("bookings/{id:int}")]
    public async Task<ActionResult<AdminBookingDetail>> Booking(int id, CancellationToken ct)
    {
        var booking = await db.Bookings.AsNoTracking().Where(item => item.Id == id).Select(item => new AdminBookingDetail(
            item.Id, item.Customer.FullName, item.Customer.Email, item.Studio.StudioName, item.Package.Name, item.BookingDate, item.StartTime, item.EndTime,
            item.Location, item.Notes, item.TotalPrice,
            item.Status == BookingStatus.Pending ? "Pending" :
            item.Status == BookingStatus.AIRecommended ? "AIRecommended" :
            item.Status == BookingStatus.AwaitingApproval ? "AwaitingApproval" :
            item.Status == BookingStatus.Confirmed ? "Confirmed" :
            item.Status == BookingStatus.Rejected ? "Rejected" :
            item.Status == BookingStatus.Cancelled ? "Cancelled" :
            item.Status == BookingStatus.Rescheduled ? "Rescheduled" : "Completed",
            item.PricingSnapshotJson, item.CreatedAt,
            item.BookingLocation == null ? null : new AdminBookingLocation(item.BookingLocation.Address, item.BookingLocation.City, item.BookingLocation.Latitude, item.BookingLocation.Longitude, item.BookingLocation.Notes),
            item.StatusHistory.OrderBy(history => history.CreatedAt).Select(history => new AdminStatusHistory(
                history.OldStatus == null ? null :
                    history.OldStatus == BookingStatus.Pending ? "Pending" :
                    history.OldStatus == BookingStatus.AIRecommended ? "AIRecommended" :
                    history.OldStatus == BookingStatus.AwaitingApproval ? "AwaitingApproval" :
                    history.OldStatus == BookingStatus.Confirmed ? "Confirmed" :
                    history.OldStatus == BookingStatus.Rejected ? "Rejected" :
                    history.OldStatus == BookingStatus.Cancelled ? "Cancelled" :
                    history.OldStatus == BookingStatus.Rescheduled ? "Rescheduled" : "Completed",
                history.NewStatus == BookingStatus.Pending ? "Pending" :
                    history.NewStatus == BookingStatus.AIRecommended ? "AIRecommended" :
                    history.NewStatus == BookingStatus.AwaitingApproval ? "AwaitingApproval" :
                    history.NewStatus == BookingStatus.Confirmed ? "Confirmed" :
                    history.NewStatus == BookingStatus.Rejected ? "Rejected" :
                    history.NewStatus == BookingStatus.Cancelled ? "Cancelled" :
                    history.NewStatus == BookingStatus.Rescheduled ? "Rescheduled" : "Completed",
                history.ChangedBy, history.Reason, history.CreatedAt)).ToList()
        )).SingleOrDefaultAsync(ct);
        return booking is null ? NotFound(new { message = "Booking not found." }) : Ok(booking);
    }

    [HttpGet("reviews")]
    public async Task<ActionResult<AdminPage<AdminReviewSummary>>> Reviews([FromQuery] AdminReviewQuery request, CancellationToken ct)
    {
        var query = db.Reviews.AsNoTracking();
        if (request.Rating.HasValue) query = query.Where(item => item.Rating == request.Rating.Value);
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            var value = request.Search.Trim().ToLower();
            query = query.Where(item => item.Customer.FullName.ToLower().Contains(value) || item.Studio.StudioName.ToLower().Contains(value) || (item.Comment ?? "").ToLower().Contains(value));
        }
        return Ok(await PageAsync(query.OrderByDescending(item => item.CreatedAt).ThenByDescending(item => item.Id).Select(review => new AdminReviewSummary(review.Id, review.Customer.FullName, review.Studio.StudioName, review.Rating, review.Comment, review.CreatedAt)), request, ct));
    }

    [HttpGet("reports")]
    public async Task<ActionResult<AdminReportsResponse>> Reports(CancellationToken ct)
    {
        var statuses = await StatusCountsAsync(ct);
        var byStudio = await db.Bookings.AsNoTracking().GroupBy(item => new { item.StudioId, item.Studio.StudioName }).OrderByDescending(group => group.Count()).ThenBy(group => group.Key.StudioId).Take(10).Select(group => new AdminCountByName(group.Key.StudioId, group.Key.StudioName, group.Count())).ToListAsync(ct);
        var packages = await db.Bookings.AsNoTracking().GroupBy(item => new { item.PackageId, item.Package.Name }).OrderByDescending(group => group.Count()).ThenBy(group => group.Key.PackageId).Take(10).Select(group => new AdminCountByName(group.Key.PackageId, group.Key.Name, group.Count())).ToListAsync(ct);
        return Ok(new AdminReportsResponse(statuses, byStudio, packages,
            await db.Reviews.Select(review => (double?)review.Rating).AverageAsync(ct),
            await db.Reviews.CountAsync(ct), await db.Bookings.CountAsync(ct), await db.Studios.CountAsync(ct), await db.Users.CountAsync(item => item.Role == "Customer", ct)));
    }

    private static IQueryable<AdminStudioSummary> StudioSummaries(IQueryable<Studio> query) => query.Select(item => new AdminStudioSummary(item.Id, item.StudioName, item.User.FullName, item.Location, item.Email, item.ContactNumber, null));

    private IQueryable<AdminBookingSummary> BookingSummaries() => BookingSummaries(db.Bookings.AsNoTracking());

    internal static IQueryable<AdminBookingSummary> BookingSummaries(IQueryable<Booking> query) => query.Select(item => new AdminBookingSummary(
        item.Id, item.Customer.FullName, item.Studio.StudioName, item.Package.Name, item.BookingDate, item.TotalPrice,
        item.Status == BookingStatus.Pending ? "Pending" :
        item.Status == BookingStatus.AIRecommended ? "AIRecommended" :
        item.Status == BookingStatus.AwaitingApproval ? "AwaitingApproval" :
        item.Status == BookingStatus.Confirmed ? "Confirmed" :
        item.Status == BookingStatus.Rejected ? "Rejected" :
        item.Status == BookingStatus.Cancelled ? "Cancelled" :
        item.Status == BookingStatus.Rescheduled ? "Rescheduled" : "Completed",
        item.CreatedAt));

    private async Task<IReadOnlyList<AdminStatusCount>> StatusCountsAsync(CancellationToken ct)
    {
        var counts = await db.Bookings.AsNoTracking().GroupBy(item => item.Status)
            .Select(group => new { Status = group.Key, Count = group.Count() }).ToListAsync(ct);
        // At most one row per enum value; aggregate in SQL, then label the small result.
        return counts.Select(item => new AdminStatusCount(item.Status.ToString(), item.Count)).OrderBy(item => item.Status).ToArray();
    }

    private static async Task<AdminPage<T>> PageAsync<T>(IQueryable<T> query, AdminCollectionQuery request, CancellationToken ct)
    {
        var total = await query.CountAsync(ct);
        var items = await query.Skip((request.Page - 1) * request.PageSize).Take(request.PageSize).ToListAsync(ct);
        return new(items, request.Page, request.PageSize, total, (int)Math.Ceiling(total / (double)request.PageSize));
    }
}
