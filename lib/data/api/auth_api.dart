import 'api_client.dart';
import 'api_result.dart';

/// The backend's view of the player (`UserDto`, snake_case JSON).
class BackendUser {
  const BackendUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.friendCode,
    required this.avatarColor,
    required this.authProvider,
    required this.isAnonymous,
    this.email,
  });

  factory BackendUser.fromJson(Map<String, dynamic> j) => BackendUser(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String,
        friendCode: j['friend_code'] as String,
        avatarColor: j['avatar_color'] as String,
        authProvider: j['auth_provider'] as String,
        isAnonymous: j['is_anonymous'] as bool,
        email: j['email'] as String?,
      );

  final String id;
  final String username;
  final String displayName;
  final String friendCode;
  final String avatarColor;
  final String authProvider;
  final bool isAnonymous;
  final String? email;
}

class AuthResult {
  const AuthResult({required this.accessToken, required this.isNewUser, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: j['access_token'] as String,
        isNewUser: j['is_new_user'] as bool,
        user: BackendUser.fromJson(j['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final bool isNewUser;
  final BackendUser user;
}

/// `/auth/*` endpoints.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Exchanges a Firebase ID token for a backend JWT (find-or-create).
  Future<ApiResult<AuthResult>> exchangeFirebaseToken(String firebaseIdToken) async {
    final r = await _client.post(
      '/auth/firebase',
      authenticated: false,
      body: {
        'firebase_token': firebaseIdToken,
        'time_zone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
    return _parse(r, AuthResult.fromJson);
  }

  Future<ApiResult<BackendUser>> me() async => _parse(await _client.get('/auth/me'), BackendUser.fromJson);

  Future<ApiResult<BackendUser>> updateProfile({String? displayName, String? avatarColor}) async => _parse(
        await _client.patch('/auth/me', body: {
          'display_name': ?displayName,
          'avatar_color': ?avatarColor,
        }),
        BackendUser.fromJson,
      );

  static ApiResult<T> _parse<T>(ApiResult<Map<String, dynamic>> r, T Function(Map<String, dynamic>) f) {
    if (!r.isSuccess) return ApiResult.failed(r.failure!, statusCode: r.statusCode, message: r.message);
    try {
      return ApiResult.success(f(r.value!), statusCode: r.statusCode);
    } on Object {
      return ApiResult.failed(ApiFailure.badResponse, statusCode: r.statusCode);
    }
  }
}
