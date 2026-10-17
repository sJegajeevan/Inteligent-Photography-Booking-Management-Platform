import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> changePassword({required String currentPassword, required String newPassword, required String confirmPassword}) async {
    await _request('api/customer/profile/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    }, token: await _profileToken(), method: 'PUT');
  }

  Future<String> _profileToken() async {
    final token = await readToken();
    if (token == null || token.isEmpty) throw const AuthApiException('Please log in again.');
    return token;
  }

  Future<AuthUser> getProfile() async => AuthUser.fromJson(
    await _request('api/customer/profile', null, token: await _profileToken()));

  Future<AuthUser> updateProfile({required String fullName, required String email, String? phoneNumber}) async => AuthUser.fromJson(
    await _request('api/customer/profile', {
      'fullName': fullName.trim(), 'email': email.trim(),
      'phoneNumber': phoneNumber == null || phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
    }, token: await _profileToken(), method: 'PUT'));

  Future<AuthUser> uploadProfilePhoto(XFile file) async {
    if (await file.length() > 5 * 1024 * 1024) throw const AuthApiException('Choose an image smaller than 5 MB.');
    final bytes = await file.readAsBytes();
    final String type;
    if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
      type = 'jpeg';
    } else if (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71) {
      type = 'png';
    } else if (bytes.length >= 12 && ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' && ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      type = 'webp';
    } else {
      throw const AuthApiException('Choose a JPEG, PNG, or WebP image.');
    }
    final request = http.MultipartRequest('POST', ApiConfig.endpoint('api/customer/profile/photo'))
      ..headers['Authorization'] = 'Bearer ${await _profileToken()}'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'profile.$type', contentType: MediaType('image', type)));
    try {
      final response = await (() async => http.Response.fromStream(await _client.send(request)))().timeout(const Duration(seconds: 45));
      return AuthUser.fromJson(_decode(response));
    } on TimeoutException {
      throw const AuthApiException('Upload timed out. Refresh your profile before trying again.');
    } on http.ClientException {
      throw const AuthApiException('Cannot upload the photo. Check your connection.');
    } on FormatException {
      throw const AuthApiException('The account server returned invalid data.');
    }
  }

  Future<AuthUser> _requestUser(String token) async => AuthUser.fromJson(await _request('api/auth/me', null, token: token));

  Future<Map<String, dynamic>> _request(String path, Map<String, dynamic>? body, {String? token, String? method}) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await (body == null
              ? _client.get(ApiConfig.endpoint(path), headers: headers)
              : method == 'PUT'
                  ? _client.put(ApiConfig.endpoint(path), headers: headers, body: jsonEncode(body))
                  : _client.post(ApiConfig.endpoint(path), headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 20));
      return _decode(response);
    } on TimeoutException {
      throw const AuthApiException('The connection timed out. Please try again.');
    } on http.ClientException {
      throw const AuthApiException('Cannot connect to the account server. Check your connection and try again.');
    } on FormatException {
      throw const AuthApiException('The account server returned invalid data.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
      if (response.statusCode == 429) throw const AuthApiException('Too many attempts. Please wait a minute and try again.');
      if (response.statusCode == 401 && response.bodyBytes.isEmpty) throw const AuthApiException('Your session has expired. Please log out and log in again.');
      if (response.statusCode == 403) throw const AuthApiException('A customer account is required.');
      if (response.statusCode == 413) throw const AuthApiException('Choose an image smaller than 5 MB.');
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
  }
}
