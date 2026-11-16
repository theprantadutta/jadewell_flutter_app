import '../api/api_result.dart';
import '../api/social_api.dart';

export '../api/social_api.dart'
    show
        Friend,
        FriendCodes,
        FriendRequest,
        FriendRequestStatus,
        FriendRequests,
        LeaderboardEntry,
        LeaderboardMe,
        LeaderboardPage,
        PlayerSummary,
        isoWeekKey,
        utcDateKey;

enum LeaderboardKind { daily, weekly, friends }

/// Why sending a friend request didn't work, for user-facing copy.
enum AddFriendError {
  /// Not a well-formed code (checked locally before any request).
  invalidCode,

  /// Your own code (checked locally).
  ownCode,

  /// No player has that code.
  notFound,

  /// Already friends, or a request is already pending.
  alreadyConnected,

  /// No connection / timeout.
  offline,

  /// The server can't do this right now (5xx, or the endpoint is missing).
  unavailable,
}

/// Leaderboards and friends. Online-only; every call degrades to a typed
/// failure instead of throwing.
abstract interface class SocialRepository {
  Future<ApiResult<LeaderboardPage>> leaderboard(LeaderboardKind kind, DateTime utcNow);
  Future<ApiResult<List<Friend>>> friends();
  Future<ApiResult<FriendRequests>> requests();

  /// [friendCode] must already be canonical (see [FriendCodes.normalize]).
  Future<({FriendRequest? request, AddFriendError? error})> sendRequest(String friendCode);
  Future<ApiResult<Friend>> accept(String requestId);
  Future<ApiResult<void>> decline(String requestId);
  Future<ApiResult<void>> cancel(String requestId);
  Future<ApiResult<void>> remove(String userId);
}

class ApiSocialRepository implements SocialRepository {
  ApiSocialRepository(this._api);

  final SocialApi _api;

  @override
  Future<ApiResult<LeaderboardPage>> leaderboard(LeaderboardKind kind, DateTime utcNow) => switch (kind) {
        LeaderboardKind.daily => _api.dailyLeaderboard(utcDateKey(utcNow)),
        LeaderboardKind.weekly => _api.weeklyLeaderboard(isoWeekKey(utcNow)),
        LeaderboardKind.friends => _api.friendsLeaderboard(utcDateKey(utcNow)),
      };

  @override
  Future<ApiResult<List<Friend>>> friends() => _api.friends();

  @override
  Future<ApiResult<FriendRequests>> requests() => _api.requests();

  @override
  Future<({FriendRequest? request, AddFriendError? error})> sendRequest(String friendCode) async {
    if (!FriendCodes.isValid(friendCode)) return (request: null, error: AddFriendError.invalidCode);
    final r = await _api.sendRequest(friendCode);
    if (r.isSuccess) return (request: r.value, error: null);
    return (request: null, error: addFriendErrorFor(r));
  }

  @override
  Future<ApiResult<Friend>> accept(String requestId) => _api.accept(requestId);

  @override
  Future<ApiResult<void>> decline(String requestId) => _api.decline(requestId);

  @override
  Future<ApiResult<void>> cancel(String requestId) => _api.cancel(requestId);

  @override
  Future<ApiResult<void>> remove(String userId) => _api.remove(userId);
}

/// Maps a failed `POST friends/requests` onto [AddFriendError]. A 404 with
/// an `error` body means "no such code"; a bare 404 means the route itself
/// is missing (backend not deployed yet).
AddFriendError addFriendErrorFor(ApiResult<Object?> r) {
  if (r.failure == ApiFailure.offlineOrTransport || r.failure == ApiFailure.timeout) {
    return AddFriendError.offline;
  }
  return switch (r.statusCode) {
    404 => r.message == null ? AddFriendError.unavailable : AddFriendError.notFound,
    409 => AddFriendError.alreadyConnected,
    400 || 422 => AddFriendError.invalidCode,
    _ => AddFriendError.unavailable,
  };
}
