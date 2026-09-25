import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

class ReviewApiException implements Exception {
  const ReviewApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

class ReviewService {
  final _auth = AuthService();
  final _client = http.Client();

  void close() {
    _auth.close();
    _client.close();
  }

  Future<void> submit({required int bookingId, required int rating, required String comment}) async {
    if (bookingId <= 0 || rating < 1 || rating > 5 || comment.length > 2000) {
      throw const ReviewApiException('Select 1–5 stars and use at most 2000 characters.');
    }
    final token = await _auth.readToken();
    if (token == null || token.isEmpty) {
      throw const ReviewApiException('Please sign in with your Customer account.', statusCode: 401);
    }
    try {
      final response = await _client.post(ApiConfig.endpoint('api/customer/reviews'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'bookingId': bookingId, 'rating': rating,
          'comment': comment.trim().isEmpty ? null : comment.trim()}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 201) return;
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw ReviewApiException('Please sign in with the Customer account that owns this booking.', statusCode: response.statusCode);
      }
      if (response.statusCode == 409) {
        throw const ReviewApiException('This booking already has a review.', statusCode: 409);
      }
      var message = response.statusCode == 404
          ? 'This booking was not found or is not available to your account.'
          : 'Unable to submit your review. Please try again later.';
      if (response.statusCode == 400) {
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map<String, dynamic>) {
            if (data['message'] is String) message = data['message'] as String;
            if (data['errors'] is Map) {
              final errors = (data['errors'] as Map).values.whereType<List>()
                  .expand((items) => items).whereType<String>().join('\n');
              if (errors.isNotEmpty) message = errors;
            }
          }
        } on FormatException {
          message = 'Check your rating and comment, then try again.';
        }
      }
      throw ReviewApiException(message, statusCode: response.statusCode);
    } on TimeoutException {
      throw const ReviewApiException('The request timed out. Your review may have been saved. Retrying cannot create a second review for this booking.');
    } on http.ClientException {
      throw const ReviewApiException('Connection interrupted. Check your connection and retry; only one review per booking can be saved.');
    }
  }
}
