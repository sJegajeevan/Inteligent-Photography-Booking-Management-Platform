using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.Reviews;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Controllers;

[ApiController]
[Authorize]
public class ReviewsController(ApplicationDbContext context) : ControllerBase
{
    [HttpPost("api/customer/reviews")]
    [Authorize(Roles = "Customer")]
    public async Task<ActionResult<ReviewResponse>> Create(
        CreateReviewRequest request, CancellationToken cancellationToken)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        // Confirm the account still exists and is a customer, even with an older JWT.
        var customer = await context.Users.AsNoTracking().SingleOrDefaultAsync(
            user => user.Id == userId && user.Role == "Customer", cancellationToken);
        if (customer is null) return Forbid();

        var booking = await context.Bookings.AsNoTracking().SingleOrDefaultAsync(
            item => item.Id == request.BookingId && item.CustomerId == userId, cancellationToken);
        if (booking is null) return NotFound(new { message = "Booking was not found." });
        if (booking.Status != BookingStatus.Completed)
            return BadRequest(new { message = "Only completed bookings can be reviewed." });

        if (await context.Reviews.AnyAsync(item => item.BookingId == booking.Id, cancellationToken))
            return Conflict(new { message = "This booking already has a review." });

        var review = new Review
        {
            BookingId = booking.Id,
            CustomerId = booking.CustomerId,
            StudioId = booking.StudioId,
            Rating = request.Rating,
            Comment = string.IsNullOrWhiteSpace(request.Comment) ? null : request.Comment.Trim(),
            CreatedAt = DateTime.UtcNow
        };
        context.Reviews.Add(review);
        try
        {
            await context.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (
            exception.InnerException is PostgresException
            {
                SqlState: PostgresErrorCodes.UniqueViolation,
                ConstraintName: "IX_Reviews_BookingId" or "IX_Reviews_BookingId_CustomerId_StudioId"
            })
        {
            // The unique index also protects against simultaneous submissions.
            return Conflict(new { message = "This booking already has a review." });
        }

        return StatusCode(StatusCodes.Status201Created, new ReviewResponse
        {
            Id = review.Id, BookingId = review.BookingId, CustomerId = review.CustomerId,
            CustomerName = customer.FullName, StudioId = review.StudioId,
            Rating = review.Rating, Comment = review.Comment, CreatedAt = review.CreatedAt
        });
    }

    [HttpGet("api/studio/reviews")]
    [Authorize(Roles = "Studio")]
    public async Task<ActionResult<IReadOnlyList<ReviewResponse>>> GetAll(CancellationToken cancellationToken)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();
        var reviews = await OwnedReviews(userId)
            .OrderByDescending(review => review.CreatedAt).ThenBy(review => review.Id)
            .ToListAsync(cancellationToken);
        return Ok(reviews);
    }

    [HttpGet("api/studio/reviews/{id:guid}")]
    [Authorize(Roles = "Studio")]
    public async Task<ActionResult<ReviewResponse>> GetById(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();
        var review = await OwnedReviews(userId).SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
        return review is null ? NotFound(new { message = "Review was not found." }) : Ok(review);
    }

    private IQueryable<ReviewResponse> OwnedReviews(int userId) => context.Reviews.AsNoTracking()
        .Where(review => review.Studio.UserId == userId && review.Studio.User.Role == "Studio")
        .Select(review => new ReviewResponse
        {
            Id = review.Id, BookingId = review.BookingId, CustomerId = review.CustomerId,
            CustomerName = review.Customer.FullName, StudioId = review.StudioId,
            Rating = review.Rating, Comment = review.Comment, CreatedAt = review.CreatedAt
        });

    private bool TryGetUserId(out int userId) =>
        int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId) && userId > 0;
}
