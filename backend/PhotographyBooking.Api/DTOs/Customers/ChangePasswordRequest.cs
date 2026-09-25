using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.Customers;

public class ChangePasswordRequest
{
    [Required, StringLength(4096)]
    public string CurrentPassword { get; set; } = string.Empty;

    // Match the existing Customer mobile registration minimum.
    [Required, StringLength(72, MinimumLength = 6)]
    public string NewPassword { get; set; } = string.Empty;

    [Required, Compare(nameof(NewPassword), ErrorMessage = "Passwords do not match.")]
    public string ConfirmPassword { get; set; } = string.Empty;
}
