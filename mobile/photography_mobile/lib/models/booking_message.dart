class BookingMessage {
  const BookingMessage({required this.id, required this.bookingId,
    required this.senderName, required this.senderRole,
    required this.message, required this.sentAt});

  final int id, bookingId;
  final String senderName, senderRole, message;
  final DateTime sentAt;

  factory BookingMessage.fromJson(Map<String, dynamic> json) => BookingMessage(
    id: json['id'] as int,
    bookingId: json['bookingId'] as int,
    senderName: json['senderName'] as String,
    senderRole: json['senderRole'] as String,
    message: json['message'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String).toUtc(),
  );
}
