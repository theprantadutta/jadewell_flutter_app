import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/api/api_result.dart';
import '../data/api/social_api.dart';
import '../data/repositories/social_repository.dart';
import '../platform/analytics/analytics_service.dart';
import 'app_providers.dart';
import 'platform_providers.dart';
import 'session_controller.dart';

final socialApiProvider = Provider<SocialApi>((ref) => SocialApi(ref.watch(apiClientProvider)));

final socialRepositoryProvider =
    Provider<SocialRepository>((ref) => ApiSocialRepository(ref.watch(socialApiProvider)));

/// Wall clock for date keys (overridable in tests).
final socialClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// "1.0.0 (1)" from the platform package info.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';
});

/// The backend user id, so social data reloads when the account changes.
final _backendUserIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider).value?.user?.id);

// ---- leaderboards ----

/// A leaderboard tab: the last page that loaded (kept across failures so a
/// flaky refresh never blanks the list) and the latest failure, if any.
class LeaderboardView {
  const LeaderboardView({this.page, this.failure, this.statusCode});

  final LeaderboardPage? page;
  final ApiFailure? failure;
  final int? statusCode;

  bool get hasData => page != null;
  bool get isEmpty => page == null || page!.isEmpty;

  /// The backend doesn't serve this yet (route missing).
  bool get isUnavailable => page == null && statusCode == 404;
}

/// One provider per tab, kept alive so switching tabs is instant.
final leaderboardProvider =
    AsyncNotifierProvider.family<LeaderboardController, LeaderboardView, LeaderboardKind>(LeaderboardController.new);

class LeaderboardController extends AsyncNotifier<LeaderboardView> {
  LeaderboardController(this.kind);

  final LeaderboardKind kind;

  @override
  Future<LeaderboardView> build() async {
    ref.keepAlive();
    ref.watch(_backendUserIdProvider);
    final previous = state.value?.page;
    final now = ref.read(socialClockProvider)().toUtc();
    final r = await ref.read(socialRepositoryProvider).leaderboard(kind, now);
    if (r.isSuccess) return LeaderboardView(page: r.value);
    return LeaderboardView(page: previous, failure: r.failure, statusCode: r.statusCode);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

// ---- friends ----

class FriendsView {
  const FriendsView({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.loaded = false,
    this.failure,
    this.statusCode,
  });

  final List<Friend> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  /// At least one successful load happened.
  final bool loaded;
  final ApiFailure? failure;
  final int? statusCode;

  bool get hasFailure => failure != null;

  FriendsView copyWith({
    List<Friend>? friends,
    List<FriendRequest>? incoming,
    List<FriendRequest>? outgoing,
  }) =>
      FriendsView(
        friends: friends ?? this.friends,
        incoming: incoming ?? this.incoming,
        outgoing: outgoing ?? this.outgoing,
        loaded: loaded,
        failure: failure,
        statusCode: statusCode,
      );
}

final friendsProvider = AsyncNotifierProvider<FriendsController, FriendsView>(FriendsController.new);

class FriendsController extends AsyncNotifier<FriendsView> {
  SocialRepository get _repo => ref.read(socialRepositoryProvider);

  @override
  Future<FriendsView> build() async {
    ref.keepAlive();
    ref.watch(_backendUserIdProvider);
    final previous = state.value;
    final (friends, requests) = await (_repo.friends(), _repo.requests()).wait;
    if (friends.isSuccess && requests.isSuccess) {
      return FriendsView(
        friends: friends.value!,
        incoming: requests.value!.incoming,
        outgoing: requests.value!.outgoing,
        loaded: true,
      );
    }
    final failed = friends.isSuccess ? requests : friends;
    return FriendsView(
      friends: previous?.friends ?? const [],
      incoming: previous?.incoming ?? const [],
      outgoing: previous?.outgoing ?? const [],
      loaded: previous?.loaded ?? false,
      failure: failed.failure,
      statusCode: failed.statusCode,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Sends a request to [canonicalCode]. Returns the error, or null on
  /// success (the lists are refreshed).
  Future<({FriendRequest? request, AddFriendError? error})> sendRequest(String canonicalCode) async {
    final own = ref.read(sessionProvider).value?.user?.friendCode;
    if (own != null && own == canonicalCode) return (request: null, error: AddFriendError.ownCode);
    final r = await _repo.sendRequest(canonicalCode);
    if (r.error == null) {
      if (r.request?.status == FriendRequestStatus.accepted) _logFriendAdded('code');
      await refresh();
    }
    return r;
  }

  Future<bool> accept(FriendRequest request) async {
    final r = await _repo.accept(request.id);
    if (!r.isSuccess) return false;
    _logFriendAdded('request');
    final v = state.value;
    if (v != null) {
      state = AsyncData(v.copyWith(
        incoming: [for (final x in v.incoming) if (x.id != request.id) x],
        friends: [...v.friends, r.value!],
      ));
    }
    return true;
  }

  Future<bool> decline(FriendRequest request) async {
    final r = await _repo.decline(request.id);
    if (!r.isSuccess) return false;
    final v = state.value;
    if (v != null) state = AsyncData(v.copyWith(incoming: [for (final x in v.incoming) if (x.id != request.id) x]));
    return true;
  }

  Future<bool> cancel(FriendRequest request) async {
    final r = await _repo.cancel(request.id);
    if (!r.isSuccess) return false;
    final v = state.value;
    if (v != null) state = AsyncData(v.copyWith(outgoing: [for (final x in v.outgoing) if (x.id != request.id) x]));
    return true;
  }

  Future<bool> remove(Friend friend) async {
    final r = await _repo.remove(friend.userId);
    if (!r.isSuccess) return false;
    final v = state.value;
    if (v != null) state = AsyncData(v.copyWith(friends: [for (final x in v.friends) if (x.userId != friend.userId) x]));
    // The friends board changed.
    ref.invalidate(leaderboardProvider(LeaderboardKind.friends));
    return true;
  }

  void _logFriendAdded(String via) {
    ref.read(analyticsProvider).log(AnalyticsEvents.friendAdded, {'via': via});
    ref.invalidate(leaderboardProvider(LeaderboardKind.friends));
  }
}
