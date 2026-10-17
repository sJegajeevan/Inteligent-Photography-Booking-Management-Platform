import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/photography_package.dart';
import 'api_config.dart';

class PackageApiException implements Exception {
  const PackageApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class PackageService {
  PackageService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  String _path(String studioId, [String? packageId]) {
    if (!isPackageGuid(studioId) ||
        (packageId != null && !isPackageGuid(packageId))) {
      throw const PackageApiException(
        'This studio or package link is invalid.',
      );
    }
    return 'api/public/studios/$studioId/packages${packageId == null ? '' : '/$packageId'}';
  }

  Future<T> _request<T>(
    String path,
    T Function(dynamic) parse, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = ApiConfig.endpoint(path);
      final response =
          await (body == null
                  ? _client.get(uri, headers: {'Accept': 'application/json'})
                  : _client.post(
                      uri,
                      headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/json',
                      },
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return parse(jsonDecode(utf8.decode(response.bodyBytes)));
      }
      String message;
      switch (response.statusCode) {
        case 400:
          message =
              'Check your package selections and quantities, then try again.';
          try {
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            if (data is Map<String, dynamic>) {
              if (data['message'] is String) {
                message = data['message'] as String;
              }
              if (data['errors'] is Map) {
                final errors = (data['errors'] as Map).values
                    .whereType<List>()
                    .expand((v) => v)
                    .whereType<String>()
                    .join(' ');
                if (errors.isNotEmpty) message = errors;
              }
            }
          } on FormatException {
            /* Keep the safe validation message. */
          }
        case 401:
          message = 'Please sign in to access this package.';
        case 403:
          message = 'This package is not available to your account.';
        case 404:
          message = 'This package is no longer available. Return to the studio to view current packages.';
        default:
          message = response.statusCode >= 500
              ? 'The package server is unavailable. Please try again later.'
              : 'Unable to load this package. Please try again.';
      }
      throw PackageApiException(message, statusCode: response.statusCode);
    } on TimeoutException {
      throw const PackageApiException(
        'The connection timed out. Please try again.',
      );
    } on http.ClientException {
      throw const PackageApiException(
        'Cannot connect to the package server. Check your connection and try again.',
      );
    } on FormatException {
      throw const PackageApiException(
        'The package server returned invalid data. Please try again.',
      );
    }
  }

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected an object');
    }
    return value;
  }

  Future<List<PhotographyPackage>> getPackages(String studioId) async =>
      _request(_path(studioId), (value) {
        if (value is! List) throw const FormatException('Expected packages');
        final packages = value
            .map((item) => PhotographyPackage.fromJson(_object(item)))
            .toList();
        if (packages.any((p) => p.studioId != studioId.toLowerCase())) {
          throw const FormatException('Wrong studio');
        }
        return packages.where((p) => p.isActive).toList();
      });

  Future<PhotographyPackage> getPackage(
    String studioId,
    String packageId,
  ) async => _request(_path(studioId, packageId), (value) {
    final package = PhotographyPackage.fromJson(_object(value));
    if (package.studioId != studioId.toLowerCase() ||
        package.id != packageId.toLowerCase()) {
      throw const FormatException('Wrong package');
    }
    if (!package.isActive) {
      throw const PackageApiException(
        'This package is no longer available.',
        statusCode: 404,
      );
    }
    return package;
  });

  Future<PackagePriceSummary> calculatePrice(
    PhotographyPackage package,
    PackageCustomization customization,
  ) async {
    final error = customization.validate(package);
    if (error != null) throw PackageApiException(error);
    return _request('${_path(package.studioId, package.id)}/calculate-price', (
      value,
    ) {
      final summary = PackagePriceSummary.fromJson(_object(value));
      final returnedAddonIds = summary.selectedAddons.map((addon) => addon.id).toSet();
      if (summary.packageId != package.id ||
          summary.extraHours != customization.extraHours ||
          summary.additionalPhotographers != customization.additionalPhotographers ||
          returnedAddonIds.length != summary.selectedAddons.length ||
          returnedAddonIds.length != customization.selectedAddonIds.length ||
          !returnedAddonIds.containsAll(customization.selectedAddonIds)) {
        throw const FormatException('Wrong price summary');
      }
      return summary;
    }, body: customization.toJson());
  }
}
