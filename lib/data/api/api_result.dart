import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why an API call failed (snake-classic's taxonomy). Bodies are never logged.
enum ApiFailure {
  /// Never reached the server: DNS, refused, no route.
  offlineOrTransport,

  /// Nothing answered in time.
  timeout,

  /// 401: the backend session is gone; re-authenticate.
  unauthorized,

  /// 403.
  forbidden,

  /// 400/409/422: refused on its merits; retrying unchanged fails the same way.
  validation,

  /// 429.
  rateLimited,

  /// 5xx.
  serverUnavailable,

  /// 2xx that could not be parsed.
  badResponse,
}

/// A value, or a reason it isn't there.
class ApiResult<T> {
  const ApiResult._({this.value, this.failure, this.statusCode, this.message});

  factory ApiResult.success(T value, {int? statusCode}) =>
      ApiResult._(value: value, statusCode: statusCode);

  factory ApiResult.failed(ApiFailure failure, {int? statusCode, String? message}) =>
      ApiResult._(failure: failure, statusCode: statusCode, message: message);

  final T? value;
  final ApiFailure? failure;
  final int? statusCode;

  /// Server-provided `error` text, safe to show in debug UI.
  final String? message;

  bool get isSuccess => failure == null;

  /// Worth retrying later without changing the request.
  bool get isTransient =>
      failure == ApiFailure.offlineOrTransport ||
      failure == ApiFailure.timeout ||
      failure == ApiFailure.rateLimited ||
      failure == ApiFailure.serverUnavailable;

  ApiResult<R> map<R>(R Function(T value) f) => isSuccess
      ? ApiResult.success(f(value as T), statusCode: statusCode)
      : ApiResult.failed(failure!, statusCode: statusCode, message: message);

  @override
  String toString() => isSuccess ? 'ApiResult.success($statusCode)' : 'ApiResult.failed(${failure!.name}, $statusCode)';
}

/// Maps HTTP responses and transport errors onto [ApiFailure].
abstract final class ApiFailureClassifier {
  static ApiResult<Map<String, dynamic>> decodeObject(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) {
      if (response.body.isEmpty) return ApiResult.success(const {}, statusCode: code);
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return ApiResult.success(decoded, statusCode: code);
        return ApiResult.success({'data': decoded}, statusCode: code);
      } on FormatException {
        return ApiResult.failed(ApiFailure.badResponse, statusCode: code);
      }
    }
    return ApiResult.failed(forStatus(code), statusCode: code, message: _errorText(response.body));
  }

  static ApiFailure forStatus(int code) => switch (code) {
        401 => ApiFailure.unauthorized,
        403 => ApiFailure.forbidden,
        429 => ApiFailure.rateLimited,
        >= 500 => ApiFailure.serverUnavailable,
        _ => ApiFailure.validation,
      };

  static ApiFailure forError(Object error) => switch (error) {
        TimeoutException() => ApiFailure.timeout,
        SocketException() || http.ClientException() || HandshakeException() => ApiFailure.offlineOrTransport,
        _ => ApiFailure.offlineOrTransport,
      };

  static String? _errorText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
    } on FormatException {
      // not JSON
    }
    return null;
  }
}
