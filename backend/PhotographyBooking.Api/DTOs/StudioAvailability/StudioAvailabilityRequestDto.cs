using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.StudioAvailability;

public class StudioAvailabilityRequestDto : IValidatableObject
{
    [Required]
    public DateOnly? Date { get; set; }

    [Required]
    public bool? IsAvailable { get; set; }

    public TimeOnly? StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }

    [StringLength(1000)]
    public string? Notes { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Date is not null && Date < DateOnly.FromDateTime(DateTime.Today))
            yield return new ValidationResult("Availability date cannot be in the past.", [nameof(Date)]);
        if (IsAvailable == true && StartTime is null)
            yield return new ValidationResult("Start time is required for an available date.", [nameof(StartTime)]);
        if (IsAvailable == true && EndTime is null)
            yield return new ValidationResult("End time is required for an available date.", [nameof(EndTime)]);
        if (StartTime is not null && EndTime is not null && EndTime <= StartTime)
            yield return new ValidationResult("End time must be later than start time.", [nameof(EndTime)]);
    }
}
