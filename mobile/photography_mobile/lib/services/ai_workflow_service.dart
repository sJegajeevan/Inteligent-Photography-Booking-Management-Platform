import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_workflow.dart';
import 'api_config.dart';
import 'auth_service.dart';

class AiWorkflowException implements Exception {
  const AiWorkflowException(this.message, {this.outcomeUnknown = false});
  final String message;
  final bool outcomeUnknown;
}

class AiWorkflowService {
  AiWorkflowService({http.Client? client, AuthService? auth})
    : _client = client ?? http.Client(),
      _auth = auth ?? AuthService();
  final http.Client _client;
  final AuthService _auth;
  void close() {
    _client.close();
    _auth.close();
  }

  static const uncertain =
      'The submission could not be confirmed. Check My AI recommendations before submitting again.';

  Future<dynamic> _request(String path, {Map<String, dynamic>? body}) async {
    var dispatched = false;
    try {
      final token = await _auth.readToken();
      if (token == null || token.isEmpty) {
        throw const AiWorkflowException(
          'Please sign in with your Customer account.',
        );
      }
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      };
      dispatched = true;
      final response =
          await (body == null
                  ? _client.get(
                      ApiConfig.endpoint('api/ai-workflows$path'),
                      headers: headers,
                    )
                  : _client.post(
                      ApiConfig.endpoint('api/ai-workflows$path'),
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(Duration(seconds: body == null ? 30 : 210));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiWorkflowException(
          'Your session has expired. Please sign in again.',
        );
      }
      if (response.statusCode == 404) {
        throw const AiWorkflowException(
          'This recommendation was not found or is not available to your account.',
        );
      }
      if (response.statusCode == 400) {
        throw const AiWorkflowException(
          'Check your requirements and try again.',
        );
      }
      if (response.statusCode != (body == null ? 200 : 201)) {
        throw AiWorkflowException(
          body == null
              ? 'Unable to load recommendations. Please refresh later.'
              : uncertain,
          outcomeUnknown: body != null,
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on AiWorkflowException {
      rethrow;
    } catch (_) {
      throw AiWorkflowException(
        body != null && dispatched
            ? uncertain
            : 'Unable to connect. Please refresh and try again.',
        outcomeUnknown: body != null && dispatched,
      );
    }
  }

  Future<AiWorkflow> submit(AiRequirements requirements) async {
    if (requirements.validate() != null) {
      throw AiWorkflowException(requirements.validate()!);
    }
    final data = await _request(
      '',
      body: {'requirements': requirements.toJson()},
    );
    try {
      return AiWorkflow.fromJson(data);
    } catch (_) {
      throw const AiWorkflowException(uncertain, outcomeUnknown: true);
    }
  }

  Future<AiWorkflow> get(String id) async {
    if (!workflowIdPattern.hasMatch(id)) {
      throw const AiWorkflowException('Recommendation not found.');
    }
    final data = await _request('/$id');
    try {
      final result = AiWorkflow.fromJson(data);
      if (result.id.toLowerCase() != id.toLowerCase()) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      throw const AiWorkflowException(
        'Unable to read this recommendation. Please refresh later.',
      );
    }
  }

  Future<AiWorkflowPage> list({int page = 1}) async {
    if (page < 1 || page > 10000) {
      throw const AiWorkflowException('Invalid page.');
    }
    final data = await _request('?page=$page&pageSize=20');
    try {
      if (data is! Map<String, dynamic> ||
          data['items'] is! List ||
          data['items'].length > 20 ||
          data['hasMore'] is! bool ||
          data['page'] != page) {
        throw const FormatException();
      }
      return AiWorkflowPage(
        (data['items'] as List).map(AiWorkflow.fromJson).toList(),
        data['hasMore'],
      );
    } catch (_) {
      throw const AiWorkflowException(
        'Unable to read recommendations. Please refresh later.',
      );
    }
  }

  Future<String?> studioName(String id) async {
    if (!workflowIdPattern.hasMatch(id)) return null;
    try {
      // Public studio metadata only; recommendation facts remain the canonical proposal.
      final response = await _client
          .get(
            ApiConfig.endpoint('api/public/studios/$id'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map<String, dynamic> && data['studioName'] is String
          ? data['studioName'] as String
          : null;
    } catch (_) {
      return null;
    }
  }
}
