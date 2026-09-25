using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.DTOs.PhotographyPackages;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

var count = 0;
void Check(bool value, string name)
{
    if (!value) throw new Exception($"FAILED: {name}");
    count++;
}
bool Valid(object value) => Validator.TryValidateObject(value, new ValidationContext(value), [], true);
var today = new DateOnly(2026, 9, 21);
var studioId = Guid.NewGuid();
var otherStudioId = Guid.NewGuid();
var start = new TimeOnly(10, 0);
var end = new TimeOnly(12, 0);
Check(BookingSlotRules.ValidateTime(today, start, end, today) is null, "Today is valid");
Check(BookingSlotRules.ValidateTime(today.AddDays(-1), start, end, today) is not null, "Past date rejected");
Check(BookingSlotRules.ValidateTime(today, start, start, today) is not null, "Zero interval rejected");
Check(BookingSlotRules.ValidateTime(today, end, start, today) is not null, "Reversed interval rejected");
var slot = new StudioAvailability { StudioId = studioId, Date = today, IsAvailable = true, StartTime = start, EndTime = end };
Check(BookingSlotRules.FitsAvailability(slot, start, end), "Exact availability fits");
Check(BookingSlotRules.FitsAvailability(slot, new(10, 30), new(11, 30)), "Contained slot fits");
Check(!BookingSlotRules.FitsAvailability(slot, new(9, 59), end), "Starts outside window");
Check(!BookingSlotRules.FitsAvailability(slot, start, new(12, 1)), "Ends outside window");
Check(!BookingSlotRules.FitsAvailability(null, start, end), "Missing availability rejected");
slot.IsAvailable = false;
Check(!BookingSlotRules.FitsAvailability(slot, start, end), "Closed availability rejected");
slot.IsAvailable = true; slot.EndTime = null;
Check(!BookingSlotRules.FitsAvailability(slot, start, end), "Incomplete availability rejected");
slot.EndTime = start;
Check(!BookingSlotRules.FitsAvailability(slot, start, end), "Invalid availability rejected");

var overlaps = BookingSlotRules.ConflictsWith(studioId, today, start, end).Compile();
foreach (var status in Enum.GetValues<BookingStatus>())
{
    var expected = status is not (BookingStatus.Cancelled or BookingStatus.Rejected or BookingStatus.Completed);
    Check(overlaps(new Booking { StudioId = studioId, BookingDate = today, StartTime = start, EndTime = end, Status = status }) == expected,
        $"Conflict behavior for {status}");
}
Check(!overlaps(new Booking { StudioId = studioId, BookingDate = today, StartTime = new(8, 0), EndTime = start }), "Back-to-back before");
Check(!overlaps(new Booking { StudioId = studioId, BookingDate = today, StartTime = end, EndTime = new(14, 0) }), "Back-to-back after");
Check(overlaps(new Booking { StudioId = studioId, BookingDate = today, StartTime = new(11, 0), EndTime = new(13, 0) }), "Partial overlap");
Check(!overlaps(new Booking { StudioId = otherStudioId, BookingDate = today, StartTime = start, EndTime = end }), "Different studio");
Check(!overlaps(new Booking { StudioId = studioId, BookingDate = today.AddDays(1), StartTime = start, EndTime = end }), "Different day");
Check(BookingSlotRules.FitsPackageDuration(2, 0, start, end), "Exact package duration");
Check(BookingSlotRules.FitsPackageDuration(1, 1, start, end), "Purchased extra hour");
Check(!BookingSlotRules.FitsPackageDuration(1, 0, start, end), "Excess duration rejected");
Check(!BookingSlotRules.FitsPackageDuration(0, 2, start, end), "Invalid package duration rejected");
Check(!BookingSlotRules.FitsPackageDuration(2, -1, start, end), "Negative extra hours rejected");
Check(BookingSlotRules.ValidateBookingTotal(0) is not null, "Zero total rejected");
Check(BookingSlotRules.ValidateBookingTotal(9999999999999999.99m) is null, "Maximum price supported");
Check(BookingSlotRules.ValidateBookingTotal(10000000000000000m) is not null, "Oversized price rejected");

var studios = new[] {
    new Studio { Id = studioId, StudioName = "Portrait House", Location = "Colombo", Description = "Wedding photography", PhotographyTypes = "Portrait, Wedding;portrait" },
    new Studio { Id = otherStudioId, StudioName = "Coast Studio", Location = "Galle", Description = "Events", PhotographyTypes = "Event" }
}.AsQueryable();
var services = new[] { new PhotographyBooking.Api.Models.StudioService { StudioId = studioId, ServiceName = "Wedding films" } }.AsQueryable();
Check(StudioDiscoveryService.ApplyFilters(studios, services, null, null, null).Count() == 2, "Null-coordinate studios remain in normal browsing");
Check(StudioDiscoveryService.ApplyFilters(studios, services, " wedding ", " COLOMBO ", "films").Single().Id == studioId, "Search/location/service combine");
Check(StudioDiscoveryService.ApplyFilters(studios, services, null, "Galle", "films").Count() == 0, "Service belongs to selected studio");
var summary = StudioDiscoveryService.ToSummary(studios.First());
Check(summary.PhotographyTypes.Count == 2 && summary.DistanceKm is null, "Public summary type deduplication");
Check(StudioDiscoveryService.PublicImageReference("C:\\private\\photo.jpg") is null, "Filesystem image hidden");
Check(StudioDiscoveryService.PublicImageReference("javascript:alert(1)") is null, "Unsafe scheme hidden");
Check(StudioDiscoveryService.PublicImageReference("//other.example/photo.jpg") is null, "Protocol-relative image hidden");
Check(StudioDiscoveryService.PublicImageReference("/uploads/photo.jpg") == "/uploads/photo.jpg", "Public relative image retained");

// Query translation only: this context never opens a connection or creates a schema.
using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>()
    .UseNpgsql("Host=localhost;Database=not_used;Username=not_used").Options);
var sql = db.Bookings.Where(BookingSlotRules.ConflictsWith(studioId, today, start, end)).ToQueryString();
Check(sql.Contains("SELECT") && sql.Contains("StartTime") && sql.Contains("EndTime"), "Conflict predicate translates to PostgreSQL");
sql = StudioDiscoveryService.ApplyFilters(db.Studios, db.StudioServices, "wedding", "colombo", "film").ToQueryString();
Check(sql.Contains("StudioServices") && sql.Contains("EXISTS"), "Discovery filters translate to PostgreSQL");
var discovery = new StudioDiscoveryService(db, new DistanceService());
foreach (var (latitude, longitude, radius) in new (double?, double?, double?)[] {
    (null, 79, null), (6, null, null), (91, 0, null), (0, -181, null), (double.NaN, 0, null),
    (0, double.PositiveInfinity, null), (0, 0, 0), (0, 0, 501), (0, 0, double.NaN)
})
{
    try { await discovery.NearbyAsync(latitude, longitude, radius); throw new Exception("Accepted invalid nearby request"); }
    catch (ArgumentException) { count++; }
}
var slotService = new BookingSlotValidationService(db);
var invalidSlot = await slotService.CheckAsync(studioId, today.AddDays(-1), start, end, today);
Check(invalidSlot.Code == SlotValidationCode.InvalidTime, "Read-only slot service rejects past date before DB access");

CustomerPhotographyRequirements Requirements(decimal? min = null, decimal max = 10000, DateOnly? latest = null,
    TimeOnly? preferredStart = null, TimeOnly? preferredEnd = null) => new() {
    PhotographyType = "Wedding", Location = "Colombo", EarliestDate = today, LatestDate = latest ?? today,
    CoverageHours = 2, MinimumBudget = min, MaximumBudget = max, PreferredStartTime = preferredStart, PreferredEndTime = preferredEnd
};
Check(Valid(Requirements()), "Valid requirement contract");
Check(!Valid(Requirements(20000)), "Inverted budget rejected");
Check(!Valid(Requirements(max: -1)), "Negative budget rejected");
Check(!Valid(Requirements(latest: today.AddDays(-1))), "Inverted dates rejected");
Check(!Valid(Requirements(preferredStart: start)), "Half time pair rejected");
Check(!Valid(Requirements(preferredStart: end, preferredEnd: start)), "Inverted preferred times rejected");
Check(Valid(Requirements(preferredStart: start, preferredEnd: end)), "Complete time preference accepted");
Check(!Valid(new CustomerPhotographyRequirements()), "Empty requirements rejected");
Check(!Valid(new RecommendationSelection()), "Empty selection IDs rejected");
var outcome = new ValidationSafetyOutput(ValidationOutcome.Fail, [new("SlotConflict", "selection", FindingSeverity.Error, "Choose another slot.")], DateTimeOffset.UtcNow);
var json = JsonSerializer.Serialize(outcome, new JsonSerializerOptions(JsonSerializerDefaults.Web));
Check(json.Contains("\"outcome\":\"Fail\"") && json.Contains("\"severity\":\"Error\""), "Stable string enum contract");
Check(JsonSerializer.Deserialize<ValidationSafetyOutput>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))?.Outcome == ValidationOutcome.Fail, "Contract JSON roundtrip");
Check(!JsonSerializer.Serialize(Requirements()).Contains("CustomerId"), "Customer identity is not accepted in requirements");

var addonId = Guid.NewGuid();
var package = new PhotographyPackage { Id = Guid.NewGuid(), StudioId = studioId, BasePrice = 5000,
    ExtraHourRate = 1000, AdditionalPhotographerRate = 2000,
    Addons = [new PackageAddon { Id = addonId, Name = "Album", Price = 1500 }] };
var quote = PackagePriceCalculationService.Calculate(package, new PackagePriceCalculationRequestDto {
    SelectedAddonIds = [addonId], ExtraHours = 2, AdditionalPhotographers = 1 });
Check(quote.Result?.FinalPrice == 10500 && quote.Result.SelectedAddons.Single().Id == addonId, "Authoritative price breakdown reused");
Check(PackagePriceCalculationService.Calculate(package, new() { SelectedAddonIds = [addonId, addonId] }).Result is null, "Duplicate addon rejected");
Check(PackagePriceCalculationService.Calculate(package, new() { SelectedAddonIds = [Guid.NewGuid()] }).Result is null, "Foreign addon rejected");
Check(PackagePriceCalculationService.Calculate(package, new() { ExtraHours = -1 }).Result is null, "Negative customization rejected");
Check(PackagePriceCalculationService.Calculate(null, new()).Result is null, "Missing package rejected");
package.BasePrice = 0; package.Price = 4200;
Check(PackagePriceCalculationService.Calculate(package, new()).Result?.FinalPrice == 4200, "Legacy base price fallback preserved");
package.ExtraHourRate = decimal.MaxValue;
Check(PackagePriceCalculationService.Calculate(package, new() { ExtraHours = 2 }).Result is null, "Price overflow rejected");

// Invalid input must fail before any dependency can perform database IO.
var proposalValidator = new RecommendationValidationService(null!, null!, slotService);
Check((await proposalValidator.CheckAsync(new(), today)).Validation.Outcome == ValidationOutcome.Fail, "Invalid selection rejected at tool boundary");
var invalidCustomization = new RecommendationSelection {
    StudioId = studioId, PackageId = package.Id, Date = today, StartTime = start, EndTime = end,
    Customization = new() { ExtraHours = 1001 }
};
Check((await proposalValidator.CheckAsync(invalidCustomization, today)).Pricing is null, "Nested customization range checked before DB");
var schedulingCount = await SchedulingChecks.RunAsync();
var endpointCount = await SchedulingEndpointChecks.RunAsync();
var finalValidationCount = await FinalValidationChecks.RunAsync();
var finalEndpointCount = await FinalValidationEndpointChecks.RunAsync();
var publicationCount = await ProposalPublicationChecks.RunAsync();
var workflowApiCount = await AiWorkflowApiChecks.RunAsync();
var pythonExecutionCount = await PythonExecutionChecks.RunAsync();
Console.WriteLine($"Passed {pythonExecutionCount} Python execution integration checks.");
Console.WriteLine($"Passed {workflowApiCount} workflow API/service checks.");
Console.WriteLine($"Passed {publicationCount} canonical publication/approval foundation checks.");
Console.WriteLine($"Passed {count} Phase 1 checks, {schedulingCount} scheduling checks, {endpointCount} scheduling endpoint checks, {finalValidationCount} final validation checks, and {finalEndpointCount} final validation endpoint checks. No database connection, schema changes, or AI provider calls.");
