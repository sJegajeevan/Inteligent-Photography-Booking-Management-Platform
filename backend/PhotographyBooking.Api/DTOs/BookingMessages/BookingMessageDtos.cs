using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.BookingMessages;

public sealed class SendBookingMessageRequest
{
    [Required, MaxLength(1000)]
    public string Message { get; set; } = string.Empty;
}

public sealed record BookingMessageResponse(int Id, int BookingId, int SenderUserId,
    string SenderName, string SenderRole, string Message, DateTime SentAt);

public sealed record BookingConversationResponse(int BookingId, string CustomerName,
    string PackageName, DateOnly BookingDate, string? LatestMessage, DateTime? LatestMessageTime);
