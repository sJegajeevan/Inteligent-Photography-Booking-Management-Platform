class StudioAvailability {
  const StudioAvailability({
    required this.date,
    required this.isAvailable,
    this.startTime,
    this.endTime,
  });

  final DateTime date;
  final bool isAvailable;
  final String? startTime, endTime;

  factory StudioAvailability.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'];
    final available = json['isAvailable'];
    if (rawDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ||
        available is! bool) {
      throw const FormatException('Invalid availability date or status');
    }
    final date = DateTime.tryParse(rawDate);
    if (date == null || date.toIso8601String().split('T').first != rawDate) {
      throw const FormatException('Invalid availability date');
    }

    String? parseTime(dynamic value) {
      if (value == null) return null;
      if (value is! String ||
          !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,7})?)?$')
              .hasMatch(value)) {
        throw const FormatException('Invalid availability time');
      }
      return value;
    }

    return StudioAvailability(
      date: date,
      isAvailable: available,
      startTime: parseTime(json['startTime']),
      endTime: parseTime(json['endTime']),
    );
  }
}
