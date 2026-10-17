import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/customer_notification.dart';
import 'api_config.dart';
import 'auth_service.dart';

class NotificationApiException implements Exception {
  const NotificationApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NotificationService {
  final _auth = AuthService();
  final _client = http.Client();
  static const _path = 'api/customer/notifications';

  void close() {
    _auth.close();
    _client.close();
  }

  Future<List<CustomerNotification>> getNotifications() async {
    final data = await _request(_path);
    try {
      return (data as List).map((item) => CustomerNotification.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      throw const NotificationApiException('The notification server returned invalid data.');
    }
  }

  Future<int> getUnreadCount() async {
    final data = await _request('$_path/unread-count');
    if (data is Map<String, dynamic> && data['unreadCount'] is int && (data['unreadCount'] as int) >= 0) {
      return data['unreadCount'] as int;
    }
    throw const NotificationApiException('The notification server returned invalid data.');
  }

  Future<void> markRead(String id) async {
    await _request('$_path/${Uri.encodeComponent(id)}/read', patch: true);
  }

  Future<dynamic> _request(String path, {bool patch = false}) async {
    try {
      final token = await _auth.readToken();
      if (token == null || token.isEmpty) throw const NotificationApiException('Please log in to view notifications.');
      final headers = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
      final response = await (patch
          ? _client.patch(ApiConfig.endpoint(path), headers: headers)
          : _client.get(ApiConfig.endpoint(path), headers: headers))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const NotificationApiException('Your customer session is unavailable. Please log out and log in again.');
      }
      if (response.statusCode == 404) throw const NotificationApiException('This notification is no longer available. Pull down to refresh.');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const NotificationApiException('Unable to load or update notifications. Please try again.');
      }
      if (response.statusCode == 204) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      throw const NotificationApiException('The request timed out. Please try again.');
    } on http.ClientException {
      throw const NotificationApiException('Cannot connect to notifications. Check your connection and retry.');
    } on FormatException {
      throw const NotificationApiException('The notification server returned invalid data.');
    }
  }
}
