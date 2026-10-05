namespace PhotographyBooking.Api.DTOs.Admin;

public record AdminDashboardResponse(
    int TotalStudios,
    int TotalCustomers,
    int TotalBookings,
    int TotalPackages,
    int TotalReviews,
    IReadOnlyList<AdminStatusCount> BookingStatuses,
    IReadOnlyList<AdminBookingSummary> RecentBookings,
    IReadOnlyList<AdminStudioSummary> RecentStudios);

public record AdminStatusCount(string Status, int Count);

public record AdminStudioSummary(Guid Id, string StudioName, string OwnerName, string Location, string Email, string ContactNumber, DateTime? CreatedAt);

public record AdminStudioDetail(
    Guid Id,
    string StudioName,
    string OwnerName,
    string OwnerEmail,
    string Location,
    string Address,
    string ContactNumber,
    string Email,
    int ExperienceYears,
    string PhotographyTypes,
    decimal StartingPrice,
    string LogoUrl,
    string CoverPhotoUrl,
    DateTime? CreatedAt,
    int PortfolioCount,
    int ServiceCount,
    int PackageCount,
    int AvailabilityCount,
    int BookingCount,
    int ReviewCount,
    double? AverageRating,
    IReadOnlyList<AdminNamedItem> Services,
    IReadOnlyList<AdminNamedItem> Packages);

public record AdminNamedItem(Guid Id, string Name, string? Category, decimal? Price, string? Status);

public record AdminCustomerSummary(int Id, string FullName, string Email, DateTime CreatedAt, int BookingCount, int ReviewCount);

public record AdminCustomerDetail(
    int Id,
    string FullName,
    string Email,
    string? PhoneNumber,
    string? ProfilePhotoUrl,
    DateTime CreatedAt,
    IReadOnlyList<AdminBookingSummary> Bookings,
    IReadOnlyList<AdminReviewSummary> Reviews);

public record AdminBookingSummary(
    int Id,
    string CustomerName,
    string StudioName,
    string PackageName,
    DateOnly BookingDate,
    decimal TotalPrice,
    string Status,
    DateTime CreatedAt);

public record AdminBookingDetail(
    int Id,
    string CustomerName,
    string CustomerEmail,
    string StudioName,
    string PackageName,
    DateOnly BookingDate,
    TimeOnly StartTime,
    TimeOnly EndTime,
    string Location,
    string? Notes,
    decimal TotalPrice,
    string Status,
    string? PricingSnapshotJson,
    DateTime CreatedAt,
    AdminBookingLocation? BookingLocation,
    IReadOnlyList<AdminStatusHistory> StatusHistory);

public record AdminBookingLocation(string Address, string City, decimal? Latitude, decimal? Longitude, string? Notes);

public record AdminStatusHistory(string? OldStatus, string NewStatus, string ChangedBy, string? Reason, DateTime CreatedAt);

public record AdminReviewSummary(Guid Id, string CustomerName, string StudioName, int Rating, string? Comment, DateTime CreatedAt);

public record AdminReportsResponse(
    IReadOnlyList<AdminStatusCount> BookingStatuses,
    IReadOnlyList<AdminCountByName> BookingsByStudio,
    IReadOnlyList<AdminCountByName> PopularPackages,
    double? AverageRating,
    int TotalReviews,
    int TotalBookings,
    int TotalStudios,
    int TotalCustomers);

public record AdminCountByName(Guid Id, string Name, int Count);

public record AdminPage<T>(IReadOnlyList<T> Items, int Page, int PageSize, int TotalCount, int TotalPages);

public class AdminCollectionQuery : System.ComponentModel.DataAnnotations.IValidatableObject
{
    [System.ComponentModel.DataAnnotations.Range(1, 10000)] public int Page { get; init; } = 1;
    [System.ComponentModel.DataAnnotations.Range(10, 100)] public int PageSize { get; init; } = 10;
    [System.ComponentModel.DataAnnotations.StringLength(200)] public string? Search { get; init; }
    public virtual IEnumerable<System.ComponentModel.DataAnnotations.ValidationResult> Validate(System.ComponentModel.DataAnnotations.ValidationContext context) => [];
}

public sealed class AdminBookingQuery : AdminCollectionQuery
{
    public PhotographyBooking.Api.Models.BookingStatus? Status { get; init; }
    public Guid? StudioId { get; init; }
    public int? CustomerId { get; init; }
    public DateOnly? FromDate { get; init; }
    public DateOnly? ToDate { get; init; }
    public override IEnumerable<System.ComponentModel.DataAnnotations.ValidationResult> Validate(System.ComponentModel.DataAnnotations.ValidationContext context)
    {
        if (Status.HasValue && !Enum.IsDefined(Status.Value)) yield return new("Invalid booking status.", [nameof(Status)]);
        if (StudioId == Guid.Empty) yield return new("Invalid studio ID.", [nameof(StudioId)]);
        if (CustomerId <= 0) yield return new("Invalid customer ID.", [nameof(CustomerId)]);
        if (FromDate > ToDate) yield return new("From date must not exceed to date.", [nameof(FromDate), nameof(ToDate)]);
    }
}

public sealed class AdminReviewQuery : AdminCollectionQuery
{
    [System.ComponentModel.DataAnnotations.Range(1, 5)] public int? Rating { get; init; }
}
