using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Customers;

public class UpdateCustomerProfileRequest
{
    [Required, StringLength(160)]
    public string FullName { get; set; } = string.Empty;

    [Required, EmailAddress, StringLength(254)]
    public string Email { get; set; } = string.Empty;

    [StringLength(30), RegularExpression(@"^\+?[0-9 ()\-]{7,30}$",
        ErrorMessage = "Enter a valid phone number (7–30 characters).")]
    public string? PhoneNumber { get; set; }
}

public record CustomerProfileResponse(int Id, string FullName, string Email,
    string Role, string? PhoneNumber, string? ProfilePhotoUrl);
