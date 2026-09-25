namespace PhotographyBooking.Api.DTOs.Customers;

public record NotificationResponse(Guid Id, string Title, string Message, string Type,
    int? BookingId, bool IsRead, DateTime CreatedAt);
