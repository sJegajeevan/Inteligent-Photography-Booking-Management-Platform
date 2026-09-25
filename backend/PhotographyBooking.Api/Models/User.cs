namespace PhotographyBooking.Api.Models;

public class User
{
    public int Id { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string Email { get; set; } = string.Empty;

    [System.ComponentModel.DataAnnotations.MaxLength(30)]
    public string? PhoneNumber { get; set; }

    [System.ComponentModel.DataAnnotations.MaxLength(2048)]
    public string? ProfilePhotoUrl { get; set; }

    public string PasswordHash { get; set; } = string.Empty;

    public string Role { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
