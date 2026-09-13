import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/auth_user.dart';
import 'api_config.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthService {
  AuthService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'customer_jwt';
  final http.Client _client;
  final FlutterSecureStorage _storage;

  void close() => _client.close();
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<AuthUser?> restoreSession() async {
    final token = await readToken();
    if (token == null || token.isEmpty) return null;
    try {
      final user = await _requestUser(token);
      if (user.role.toLowerCase() != 'customer') {
        await logout();
        return null;
      }
      return user;
    } on AuthApiException {
      await logout();
      return null;
    } on FormatException {
      await logout();
      return null;
    }
  }

  Future<AuthUser> login(String email, String password) async {
    final data = await _request('api/auth/login', {'email': email.trim(), 'password': password});
    final token = data['token'];
    final user = data['user'];
    if (token is! String || user is! Map<String, dynamic>) throw const AuthApiException('The login response was invalid.');
    final parsed = AuthUser.fromJson(user);
    if (parsed.role.toLowerCase() != 'customer') throw const AuthApiException('This mobile app is for customer accounts.');
    await _storage.write(key: _tokenKey, value: token);
    return parsed;
  }

  Future<void> register({required String fullName, required String email, required String password}) async {
    await _request('api/auth/register', {'fullName': fullName.trim(), 'email': email.trim(), 'password': password, 'role': 'Customer'});
  }

  Future<void> logout() => _storage.delete(key: _tokenKey);

  Future<AuthUser> _requestUser(String token) async => AuthUser.fromJson(await _request('api/auth/me', null, token: token));

  Future<Map<String, dynamic>> _request(String path, Map<String, dynamic>? body, {String? token}) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await (body == null
              ? _client.get(ApiConfig.endpoint(path), headers: headers)
              : _client.post(ApiConfig.endpoint(path), headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 20));
      final decoded = response.bodyBytes.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map<String, dynamic>) {
        final errors = decoded['errors'];
        if (errors is Map) {
          final details = errors.values.whereType<List>().expand((items) => items).whereType<String>().join(' ');
          if (details.isNotEmpty) throw AuthApiException(details);
        }
        if (decoded['message'] is String) throw AuthApiException(decoded['message'] as String);
      }
      throw AuthApiException(response.statusCode >= 500 ? 'The account server is unavailable. Please try again later.' : 'Unable to complete this request. Please try again.');
    } on TimeoutException {
      throw const AuthApiException('The connection timed out. Please try again.');
    } on http.ClientException {
      throw const AuthApiException('Cannot connect to the account server. Check your connection and try again.');
    } on FormatException {
      throw const AuthApiException('The account server returned invalid data.');
    }
  }
}