import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_result.dart';
import 'install_identity.dart';

/// Thin HTTP client for the Jadewell API. Never blocks gameplay: callers get
/// an [ApiResult] and decide; nothing here retries (the sync engine does).
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.identity,
    required this.tokenProvider,
    this.onUnauthorized,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  /// Includes the version prefix, e.g. `https://jadewell.pranta.dev/api/v1`.
  final String baseUrl;
  final InstallIdentity identity;

  /// Returns the current backend JWT, or null.
  final String? Function() tokenProvider;

  /// Called on any 401 so the session layer can re-mint the JWT.
  final void Function()? onUnauthorized;
  final Duration timeout;
  final http.Client _http;

  Future<ApiResult<Map<String, dynamic>>> get(String path, {bool authenticated = true}) =>
      send('GET', path, authenticated: authenticated);

  Future<ApiResult<Map<String, dynamic>>> post(String path, {Object? body, bool authenticated = true}) =>
      send('POST', path, body: body, authenticated: authenticated);

  Future<ApiResult<Map<String, dynamic>>> patch(String path, {Object? body}) =>
      send('PATCH', path, body: body);

  Future<ApiResult<Map<String, dynamic>>> delete(String path) => send('DELETE', path);

  Future<ApiResult<Map<String, dynamic>>> send(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final token = authenticated ? tokenProvider() : null;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...identity.headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _http.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed).timeout(timeout);
      final result = ApiFailureClassifier.decodeObject(response);
      if (result.failure == ApiFailure.unauthorized && authenticated) onUnauthorized?.call();
      return result;
    } on Object catch (e) {
      return ApiResult.failed(ApiFailureClassifier.forError(e));
    }
  }

  void close() => _http.close();
}
