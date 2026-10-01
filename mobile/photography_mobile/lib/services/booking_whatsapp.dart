import 'booking_service.dart';

/// Accept Sri Lankan national numbers and +94/94 international numbers.
/// Reject unexpected characters rather than silently stripping extensions or text.
String? normalizeWhatsAppNumber(String? value) {
  if (value == null) return null;
  final compact = value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(compact)) return null;
  var number = compact.startsWith('+') ? compact.substring(1) : compact;
  if (!compact.startsWith('+') && RegExp(r'^0[1-9][0-9]{8}$').hasMatch(number)) {
    number = '94${number.substring(1)}';
  }
  return RegExp(r'^94[1-9][0-9]{8}$').hasMatch(number) ? number : null;
}

Uri? bookingWhatsAppUrl(CustomerBookingDetails booking) {
  final number = normalizeWhatsAppNumber(booking.studioContactNumber);
  if (number == null) return null;
  final studio = booking.studioName?.trim();
  final date = booking.date!;
  final dateText = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String time(String? value) => value != null && RegExp(r'^\d{2}:\d{2}').hasMatch(value)
      ? value.substring(0, 5) : 'Not specified';
  final message = 'Hi, I have a booking with ${studio == null || studio.isEmpty ? 'your studio' : studio}.\n'
      'Booking #${booking.summary.id}\nDate: $dateText\n'
      'Time: ${time(booking.startTime)} - ${time(booking.endTime)}\n\n'
      'I would like to discuss my booking.';
  return Uri.https('wa.me', '/$number', {'text': message});
}
