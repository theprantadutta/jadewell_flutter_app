/// Makes events safe to send to Firebase Analytics: valid names, no PII,
/// bounded values. Pure Dart, shared by every [AnalyticsService] impl so the
/// debug log shows exactly what release would send.
///
/// Firebase rules (https://firebase.google.com/docs/reference/cpp/group/event-names):
/// names are 1–40 chars of `[A-Za-z0-9_]` starting with a letter, may not use
/// the `firebase_`, `google_` or `ga_` prefixes or a reserved event name;
/// string values ≤ 100 chars; at most 25 params; values are String or num.
abstract final class AnalyticsSanitizer {
  static const int maxNameLength = 40;
  static const int maxValueLength = 100;
  static const int maxParams = 25;

  static const List<String> _reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  /// Events the SDK owns. Logging one of these by hand is rejected, so ours
  /// are prefixed instead (e.g. a future `ad_reward` becomes `jw_ad_reward`).
  static const Set<String> reservedEvents = {
    'ad_activeview', 'ad_click', 'ad_exposure', 'ad_query', 'ad_reward', 'adunit_exposure',
    'app_background', 'app_clear_data', 'app_exception', 'app_remove', 'app_store_refund',
    'app_store_subscription_cancel', 'app_store_subscription_convert', 'app_store_subscription_renew',
    'app_uninstall', 'app_update', 'app_upgrade', 'dynamic_link_app_open', 'dynamic_link_app_update',
    'dynamic_link_first_open', 'error', 'first_open', 'first_visit', 'in_app_purchase',
    'notification_dismiss', 'notification_foreground', 'notification_open', 'notification_receive',
    'os_update', 'screen_view', 'session_start', 'session_start_with_rollout', 'user_engagement',
  };

  /// Param keys that could carry personal data. Dropped whatever the value.
  static const Set<String> _piiKeys = {
    'email', 'mail', 'name', 'display_name', 'displayname', 'username', 'user_name', 'first_name',
    'last_name', 'full_name', 'phone', 'phone_number', 'address', 'uid', 'user_id', 'userid',
    'firebase_uid', 'install_id', 'device_id', 'token', 'id_token', 'access_token', 'password',
    'ip', 'ip_address', 'friend_code', 'invite_code', 'lat', 'lng', 'latitude', 'longitude', 'location',
  };

  static final RegExp _invalidChars = RegExp(r'[^A-Za-z0-9_]');
  static final RegExp _email = RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+');

  /// A valid Firebase name, or null if nothing usable is left.
  static String? name(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[\s\-.:/]+'), '_').replaceAll(_invalidChars, '');
    s = s.replaceAll(RegExp(r'_+'), '_');
    if (s.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]').hasMatch(s)) s = 'e_$s';
    final lower = s.toLowerCase();
    for (final p in _reservedPrefixes) {
      if (lower.startsWith(p)) s = 'jw_${s.substring(p.length)}';
    }
    return s.length > maxNameLength ? s.substring(0, maxNameLength) : s;
  }

  /// A valid, non-reserved event name, or null.
  static String? eventName(String raw) {
    final s = name(raw);
    if (s == null) return null;
    if (reservedEvents.contains(s.toLowerCase())) {
      final p = 'jw_$s';
      return p.length > maxNameLength ? p.substring(0, maxNameLength) : p;
    }
    return s;
  }

  static const int maxUserPropertyNameLength = 24;
  static const int maxUserPropertyValueLength = 36;

  /// A valid user property name (≤ 24 chars, not reserved), or null.
  static String? userPropertyName(String raw) {
    final s = name(raw);
    if (s == null) return null;
    return s.length > maxUserPropertyNameLength ? s.substring(0, maxUserPropertyNameLength) : s;
  }

  /// A user property value: ≤ 36 chars, never an e-mail address.
  static String? userPropertyValue(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty || _email.hasMatch(s)) return null;
    return s.length > maxUserPropertyValueLength ? s.substring(0, maxUserPropertyValueLength) : s;
  }

  /// Screen names allow any text but are capped like string values.
  static String screenName(String raw) => _cap(raw.trim().isEmpty ? 'unknown' : raw.trim());

  /// Cleaned params: valid keys, PII keys and e-mail-looking strings dropped,
  /// bools as 0/1, strings ≤ 100 chars, non-finite numbers dropped, ≤ 25 entries.
  static Map<String, Object> params(Map<String, Object?> raw) {
    final out = <String, Object>{};
    for (final e in raw.entries) {
      if (out.length >= maxParams) break;
      final key = name(e.key);
      if (key == null || _piiKeys.contains(key.toLowerCase())) continue;
      final v = _value(e.value);
      if (v != null) out[key] = v;
    }
    return out;
  }

  static Object? _value(Object? v) {
    switch (v) {
      case null:
        return null;
      case final bool b:
        return b ? 1 : 0;
      case final int i:
        return i;
      case final double d:
        return d.isFinite ? d : null;
      case final Enum e:
        return e.name;
      case final Duration d:
        return d.inMilliseconds;
      case final String s:
        return _text(s);
      default:
        return _text(v.toString());
    }
  }

  static String? _text(String s) {
    if (_email.hasMatch(s)) return null;
    return _cap(s);
  }

  static String _cap(String s) => s.length > maxValueLength ? s.substring(0, maxValueLength) : s;
}
