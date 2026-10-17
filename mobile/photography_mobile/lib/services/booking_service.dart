import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/photography_package.dart';
import '../models/booking_message.dart';
import '../models/studio_availability.dart';
import 'api_config.dart';
import 'auth_service.dart';

class BookingApiException implements Exception {
  const BookingApiException(this.message, {this.outcomeUnknown = false, this.statusCode});
  final String message;
  final bool outcomeUnknown;
  final int? statusCode;
}

class CreatedBooking {
  const CreatedBooking({this.id, this.status, this.totalPrice});
  final int? id;
  final String? status;
  final double? totalPrice;

  factory CreatedBooking.fromCreationJson(Map<String, dynamic> json) {
    const statusNames = ['Pending', 'AIRecommended', 'AwaitingApproval',
      'Confirmed', 'Rejected', 'Cancelled', 'Rescheduled', 'Completed'];
    final id = json['id'];
    final status = json['status'];
    final price = json['totalPrice'];
    final validStatus = status is int
        ? status >= 0 && status < statusNames.length
        : status is String && statusNames.contains(status);
    if (id is! int || id <= 0 || !validStatus ||
        price is! num || !price.isFinite || price <= 0 ||
        !price.toDouble().isFinite) {
      throw const FormatException('Invalid booking creation response');
    }
    return CreatedBooking.fromJson(json);
  }

  factory CreatedBooking.fromJson(Map<String, dynamic> json) {
    const statuses = ['Pending', 'AI Recommended', 'Awaiting Approval',
      'Confirmed', 'Rejected', 'Cancelled', 'Rescheduled', 'Completed'];
    final status = json['status'];
    final price = json['totalPrice'];
    return CreatedBooking(
      id: json['id'] is int ? json['id'] as int : null,
      status: status is int && status >= 0 && status < statuses.length
          ? statuses[status] : status is String ? status : null,
      totalPrice: price is num && price.isFinite ? price.toDouble() : null,
    );
  }
}

class BookingService {
  final _client = http.Client();
  final _auth = AuthService();

  Future<dynamic> _messagesRequest(int bookingId, {String? message}) async {
    final sending = message != null;
    try {
      final token = await _auth.readToken();
      if (token == null || token.isEmpty) {
        throw const BookingApiException('Please sign in to view this conversation.', statusCode: 401);
      }
      final uri = ApiConfig.endpoint('api/bookings/$bookingId/messages');
      final headers = {'Accept': 'application/json', 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'};
      final response = await (sending
          ? _client.post(uri, headers: headers, body: jsonEncode({'message': message}))
          : _client.get(uri, headers: headers)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw BookingApiException('Please sign in with the Customer account that owns this booking.', statusCode: response.statusCode);
      }
      if (response.statusCode == 404) {
        throw const BookingApiException('This conversation is not available to your account.', statusCode: 404);
      }
      if (response.statusCode != (sending ? 201 : 200)) {
        throw BookingApiException('Unable to ${sending ? 'send message' : 'load conversation'}. Please try again.',
          outcomeUnknown: sending && response.statusCode >= 500, statusCode: response.statusCode);
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      throw BookingApiException('Connection timed out. Refresh the conversation before trying again.', outcomeUnknown: sending);
    } on http.ClientException {
      throw BookingApiException('Cannot connect. Refresh the conversation before trying again.', outcomeUnknown: sending);
    } on FormatException {
      throw BookingApiException('Invalid server response. Refresh the conversation before trying again.', outcomeUnknown: sending);
    }
  }

  Future<List<BookingMessage>> getMessages(int bookingId) async {
    final data = await _messagesRequest(bookingId);
    try {
      return (data as List).map((item) => BookingMessage.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      throw const BookingApiException('Invalid conversation data. Please refresh.');
    }
  }

  Future<BookingMessage> sendMessage(int bookingId, String message) async {
    if (message.trim().isEmpty || message.length > 1000) {
      throw const BookingApiException('Message must contain between 1 and 1000 characters.');
    }
    final data = await _messagesRequest(bookingId, message: message.trim());
    try {
      return BookingMessage.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      throw const BookingApiException('Delivery is uncertain. Refresh the conversation before trying again.', outcomeUnknown: true);
    }
  }

  void close() {
    _client.close();
    _auth.close();
  }

  Future<List<CustomerBooking>> getMyBookings() async {
    try {
      final token = await _auth.readToken();
      if (token == null || token.isEmpty) {
        throw const BookingApiException('Please sign in to view your bookings.');
      }
      final response = await _client.get(ApiConfig.endpoint('api/bookings'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const BookingApiException('Please sign in with your Customer account to view bookings.');
      }
      if (response.statusCode != 200) {
        throw const BookingApiException('Unable to load your bookings. Please try again later.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! List) throw const FormatException('Expected booking list');
      return data.map((item) {
        if (item is! Map<String, dynamic>) throw const FormatException('Invalid booking');
        return CustomerBooking.fromJson(item);
      }).toList();
    } on TimeoutException {
      throw const BookingApiException('Loading bookings timed out. Please try again.');
    } on http.ClientException {
      throw const BookingApiException('Cannot connect. Check your connection and try again.');
    } on FormatException {
      throw const BookingApiException('The server returned invalid booking data. Please try again later.');
    }
  }

  Future<CustomerBookingDetails> getBooking(int bookingId) async {
    if (bookingId <= 0) {
      throw const BookingApiException('Booking not found.', statusCode: 404);
    }
    try {
      final token = await _auth.readToken();
      if (token == null || token.isEmpty) {
        throw const BookingApiException('Please sign in to view this booking.', statusCode: 401);
      }
      final response = await _client.get(ApiConfig.endpoint('api/bookings/$bookingId'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw BookingApiException('Please sign in with the Customer account that owns this booking.', statusCode: response.statusCode);
      }
      if (response.statusCode == 404) {
        throw const BookingApiException('This booking was not found or is not available to your account.', statusCode: 404);
      }
      if (response.statusCode != 200) {
        throw BookingApiException('Unable to load booking details. Please try again later.', statusCode: response.statusCode);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException('Invalid booking');
      final booking = CustomerBookingDetails.fromJson(data);
      if (booking.summary.id != bookingId) throw const FormatException('Wrong booking');
      return booking;
    } on TimeoutException {
      throw const BookingApiException('Loading booking details timed out. Please try again.');
    } on http.ClientException {
      throw const BookingApiException('Cannot connect. Check your connection and try again.');
    } on FormatException {
      throw const BookingApiException('The server returned invalid booking details. Please try again later.');
    }
  }

  Future<CreatedBooking> create({
    required PhotographyPackage package,
    required PackageCustomization customization,
    required StudioAvailability slot,
    required String location,
    required String notes,
  }) async {
    final token = await _auth.readToken();
    if (token == null || token.isEmpty) {
      throw const BookingApiException('Please sign in before confirming your booking.');
    }
    try {
      final response = await _client.post(ApiConfig.endpoint('api/bookings'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'studioId': package.studioId,
          'packageId': package.id,
          'bookingDate': slot.date.toIso8601String().split('T').first,
          'startTime': slot.startTime,
          'endTime': slot.endTime,
          'location': location.trim(),
          'notes': notes.trim().isEmpty ? null : notes.trim(),
          ...customization.toJson(),
        }),
      ).timeout(const Duration(seconds: 30));
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        // HTTP status still determines whether creation succeeded.
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          if (data is! Map<String, dynamic>) {
            throw const FormatException('Missing booking creation response');
          }
          return CreatedBooking.fromCreationJson(data);
        } on FormatException {
          throw const BookingApiException(
            'The server reported success, but the booking details could not be verified. Open My Bookings to check whether your booking was saved before submitting again.',
            outcomeUnknown: true,
          );
        }
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const BookingApiException('Please sign in with your Customer account to book.');
      }
      if (response.statusCode >= 500) {
        throw const BookingApiException(
          'The booking server could not complete the response. Booking creation could not be verified. Open My Bookings before submitting again.',
          outcomeUnknown: true,
        );
      }
      var message = 'Unable to create this booking. Check your details and try again.';
      if (data is Map<String, dynamic>) {
        if (data['message'] is String) message = data['message'] as String;
        if (data['errors'] is Map) {
          final errors = (data['errors'] as Map).values.whereType<List>()
              .expand((items) => items).whereType<String>().join('\n');
          if (errors.isNotEmpty) message = errors;
        }
      }
      throw BookingApiException(message);
    } on TimeoutException {
      throw const BookingApiException(
        'The request timed out. Your booking may have been saved. Open My Bookings before submitting again.',
        outcomeUnknown: true,
      );
    } on http.ClientException {
      throw const BookingApiException(
        'The connection was interrupted. Your booking may have been saved. Open My Bookings before submitting again.',
        outcomeUnknown: true,
      );
    }
  }
}

class CustomerBooking {
  CustomerBooking.fromJson(Map<String, dynamic> json)
      : summary = CreatedBooking.fromJson(json),
        date = DateTime.tryParse(json['bookingDate'] is String ? json['bookingDate'] as String : ''),
        startTime = json['startTime'] is String ? json['startTime'] as String : null,
        endTime = json['endTime'] is String ? json['endTime'] as String : null,
        studioId = json['studioId'] is String ? json['studioId'] as String : null,
        studioName = json['studioName'] is String ? json['studioName'] as String : null,
        studioContactNumber = json['studioContactNumber'] is String ? json['studioContactNumber'] as String : null,
        packageId = json['packageId'] is String ? json['packageId'] as String : null,
        packageName = json['packageName'] is String && (json['packageName'] as String).trim().isNotEmpty
            ? json['packageName'] as String
            : json['customization'] is Map && json['customization']['packageName'] is String
            ? json['customization']['packageName'] as String : null {
    if (summary.id == null || summary.id! <= 0 || date == null) {
      throw const FormatException('Invalid booking reference or date');
    }
  }

  final CreatedBooking summary;
  final DateTime? date;
  final String? startTime, endTime, studioId, studioName, packageId, packageName;
  final String? studioContactNumber;
}

class CustomerBookingDetails extends CustomerBooking {
  CustomerBookingDetails.fromJson(super.json)
      : location = json['location'] is String ? json['location'] as String : null,
        notes = json['notes'] is String ? json['notes'] as String : null,
        customization = json['customization'] is Map<String, dynamic>
            ? PackagePriceSummary.fromJson(json['customization'] as Map<String, dynamic>) : null,
        super.fromJson();

  final String? location, notes;
  final PackagePriceSummary? customization;
}
