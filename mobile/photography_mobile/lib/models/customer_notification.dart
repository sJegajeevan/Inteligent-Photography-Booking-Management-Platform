class CustomerNotification {
  const CustomerNotification({required this.id, required this.title,
    required this.message, required this.type, required this.bookingId,
    required this.isRead, required this.createdAt});

  final String id;
  final String title;
  final String message;
  final String type;
  final int? bookingId;
  final bool isRead;
  final DateTime createdAt;

  factory CustomerNotification.fromJson(Map<String, dynamic> json) => CustomerNotification(
    id: json['id'] as String,
    title: json['title'] as String,
    message: json['message'] as String,
    type: json['type'] as String,
    bookingId: json['bookingId'] as int?,
    isRead: json['isRead'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  CustomerNotification asRead() => CustomerNotification(id: id, title: title,
    message: message, type: type, bookingId: bookingId, isRead: true, createdAt: createdAt);
}
