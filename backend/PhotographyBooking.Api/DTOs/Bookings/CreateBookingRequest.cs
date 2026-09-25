using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Bookings;

public class CreateBookingRequest : IValidatableObject
{
    public Guid StudioId { get; set; }

    public Guid PackageId { get; set; }

    [Required]
    public List<Guid> SelectedAddonIds { get; set; } = [];

    [Range(0, 1000)]
    public int ExtraHours { get; set; }

    [Range(0, 100)]
    public int AdditionalPhotographers { get; set; }

    public DateOnly BookingDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }

    [Required]
    [MaxLength(500)]
    public string Location { get; set; } = string.Empty;

    [MaxLength(1_000)]
    public string? Notes { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (StudioId == Guid.Empty)
            yield return new ValidationResult("Select a valid studio.", [nameof(StudioId)]);
        if (PackageId == Guid.Empty)
            yield return new ValidationResult("Select a valid package.", [nameof(PackageId)]);
    }
}
