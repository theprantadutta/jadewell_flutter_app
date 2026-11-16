import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the backend JWT (device-only state, so SharedPreferences rather
/// than Drift, per the one-store-per-datum rule).
class SessionStore {
  SessionStore(this._prefs);

  static const _tokenKey = 'backend_jwt';
  static const _userIdKey = 'backend_user_id';

  final SharedPreferences _prefs;

  String? get token => _prefs.getString(_tokenKey);
  String? get userId => _prefs.getString(_userIdKey);

  Future<void> save({required String token, required String userId}) async {
    await _prefs.setString(_tokenKey, token);
    await _prefs.setString(_userIdKey, userId);
  }

  Future<void> clear() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userIdKey);
  }

  /// True when there is a token that won't expire in the next 5 minutes.
  bool get hasUsableToken {
    final exp = _expiry(token);
    return exp != null && DateTime.now().isBefore(exp.subtract(const Duration(minutes: 5)));
  }

  static DateTime? _expiry(String? jwt) {
    if (jwt == null) return null;
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final claims = jsonDecode(payload);
      if (claims is! Map || claims['exp'] is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000);
    } on FormatException {
      return null;
    }
  }
}
