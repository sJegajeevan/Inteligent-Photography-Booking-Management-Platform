import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/studio.dart';
import 'api_config.dart';

class StudioApiException implements Exception {
  const StudioApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StudioService {
  StudioService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<dynamic> _get(String path) async {
    try {
      final response = await _client
          .get(
            ApiConfig.endpoint(path),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 20));
      switch (response.statusCode) {
        case 200:
          return jsonDecode(utf8.decode(response.bodyBytes));
        case 401:
          throw const StudioApiException(
            'The studio service rejected this request. Please refresh and try again.',
          );
        case 403:
          throw const StudioApiException(
            'You do not have permission to view these studios. Contact support if this continues.',
          );
        case 404:
          throw const StudioApiException(
            'The studio list or requested studio could not be found.',
          );
        case 408:
          throw const StudioApiException(
            'The studio service took too long to respond. Please try again.',
          );
        case 429:
          throw const StudioApiException(
            'Too many requests. Wait a moment, then try again.',
          );
        default:
          throw StudioApiException(
            response.statusCode >= 500
                ? 'The studio service is temporarily unavailable (${response.statusCode}). Please try again shortly.'
                : 'The request could not be completed (${response.statusCode}). Please try again.',
          );
      }
    } on TimeoutException {
      throw const StudioApiException(
        'The connection timed out. Please try again.',
      );
    } on http.ClientException {
      throw const StudioApiException(
        'Could not reach the studio service. Check your internet connection and make sure the API server is running.',
      );
    } on FormatException {
      throw const StudioApiException(
        'The studio server returned an invalid response. Please try again.',
      );
    }
  }

  Studio _parse(dynamic json) {
    try {
      if (json is! Map<String, dynamic>) throw const FormatException();
      return Studio.fromJson(json);
    } on FormatException {
      throw const StudioApiException(
        'The studio server returned invalid studio data.',
      );
    }
  }

  Future<List<Studio>> getStudios() async {
    final json = await _get('api/public/studios');
    if (json is! List) {
      throw const StudioApiException(
        'The studio server returned an invalid studio list.',
      );
    }
    return json.map(_parse).toList();
  }

  Future<Studio> getStudio(String id) async =>
      _parse(await _get('api/public/studios/${Uri.encodeComponent(id)}'));
}
