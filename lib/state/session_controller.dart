import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_result.dart';
import '../data/api/auth_api.dart';
import '../platform/auth/auth_service.dart';
import 'app_providers.dart';
import 'data_providers.dart';
import 'entitlement_providers.dart';

/// The player's backend session. Offline-first: the app works without it;
/// it is established opportunistically and retried on demand.
class BackendSession {
  const BackendSession({required this.identity, this.user, this.isNewUser = false, this.lastFailure});

  /// Firebase identity (always present once signed in, even offline).
  final AuthIdentity identity;

  /// Backend profile, null until the first successful exchange.
  final BackendUser? user;
  final bool isNewUser;

  /// Why the last backend attempt failed, if it did.
  final ApiFailure? lastFailure;

  bool get isOnline => user != null && lastFailure == null;
}

/// How Settings > Account > Delete account ended.
enum DeleteAccountOutcome {
  /// Server account gone, device wiped, a fresh guest started.
  deleted,

  /// The player backed out (the Apple re-authentication sheet); nothing changed.
  cancelled,

  /// No connection; nothing changed.
  offline,

  /// The server refused or failed; nothing changed.
  failed,
}

final sessionProvider = AsyncNotifierProvider<SessionController, BackendSession>(SessionController.new);

/// Firebase guest sign-in → `POST /auth/firebase` → JWT (snake-classic flow).
class SessionController extends AsyncNotifier<BackendSession> {
  Future<void>? _inFlight;
  DateTime? _lastExchange;
  StreamSubscription<AuthIdentity?>? _authSub;
  String? _exchangedUid;

  AuthService get _auth => ref.read(authServiceProvider);

  @override
  Future<BackendSession> build() async {
    ref.keepAlive();
    _authSub = _auth.changes.listen(_onAuthChanged);
    ref.onDispose(() => _authSub?.cancel());

    final identity = await _auth.ensureSignedIn();
    final store = ref.read(sessionStoreProvider);

    // A stored token for this same Firebase user: use it and refresh the
    // profile in the background, without blocking start-up.
    if (store.hasUsableToken) {
      _exchangedUid = identity.uid;
      unawaited(Future(refreshProfile));
      return BackendSession(identity: identity);
    }
    unawaited(Future(() => ensureBackendSession(force: true)));
    return BackendSession(identity: identity);
  }

  /// Exchanges the Firebase token for a backend JWT. Coalesced (one request
  /// at a time) and rate-limited to once a minute unless [force]d.
  Future<void> ensureBackendSession({bool force = false}) {
    if (_inFlight != null) return _inFlight!;
    final last = _lastExchange;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) {
      return Future.value();
    }
    return _inFlight = _exchange(forceRefreshToken: force).whenComplete(() => _inFlight = null);
  }

  /// Called by the API client on a 401.
  void onUnauthorized() {
    unawaited(ref.read(sessionStoreProvider).clear());
    unawaited(ensureBackendSession());
  }

  Future<void> _exchange({bool forceRefreshToken = false}) async {
    _lastExchange = DateTime.now();
    final identity = _auth.current ?? await _auth.ensureSignedIn();
    final idToken = await _auth.idToken(forceRefresh: forceRefreshToken);
    if (idToken == null) return;

    final result = await ref.read(authApiProvider).exchangeFirebaseToken(idToken);
    if (!result.isSuccess) {
      debugPrint('session: backend exchange failed (${result.failure!.name}, ${result.statusCode})');
      state = AsyncData(BackendSession(identity: identity, user: state.value?.user, lastFailure: result.failure));
      return;
    }
    final auth = result.value!;
    await ref.read(sessionStoreProvider).save(token: auth.accessToken, userId: auth.user.id);
    _exchangedUid = identity.uid;
    debugPrint('session: backend user ${auth.user.username} (${auth.user.friendCode}) new=${auth.isNewUser}');
    state = AsyncData(BackendSession(identity: identity, user: auth.user, isNewUser: auth.isNewUser));
  }

  /// Re-reads `/auth/me` (e.g. after a profile edit); cheaper than a re-exchange.
  Future<void> refreshProfile() async {
    final result = await ref.read(authApiProvider).me();
    final identity = _auth.current!;
    if (result.isSuccess) {
      state = AsyncData(BackendSession(identity: identity, user: result.value));
    } else if (result.failure != ApiFailure.unauthorized) {
      // 401 already triggered a re-exchange via onUnauthorized.
      state = AsyncData(BackendSession(identity: identity, lastFailure: result.failure));
    }
  }

  void _onAuthChanged(AuthIdentity? identity) {
    // Linking keeps the uid but changes providers; signing in to another
    // account changes the uid. Either way the backend row must be updated.
    if (identity == null) return;
    final current = state.value;
    final providersChanged = current != null && current.identity.providers.length != identity.providers.length;
    if (identity.uid != _exchangedUid || providersChanged) {
      unawaited(ensureBackendSession(force: true));
    }
  }

  // ---- account actions used by the Account screen ----

  Future<void> linkGoogle() => _afterAuth(_auth.linkGoogle);
  Future<void> linkApple() => _afterAuth(_auth.linkApple);
  Future<void> linkEmail(String email, String password) =>
      _afterAuth(() => _auth.linkEmailPassword(email: email, password: password));
  Future<void> signInWithGoogle() => _afterAuth(_auth.signInWithGoogle);
  Future<void> signInWithApple() => _afterAuth(_auth.signInWithApple);
  Future<void> signInWithEmail(String email, String password) =>
      _afterAuth(() => _auth.signInWithEmailPassword(email: email, password: password));
  Future<void> signOut() => _afterAuth(_auth.signOutToGuest);

  /// Settings > Account > Delete account (PRIVACY.md §9). Deletes the
  /// server account first; only when that succeeded is the device wiped
  /// (progress, saved games, results, daily entries, streak, the unsent
  /// outbox, the local entitlement; device settings stay), the player signed
  /// out of Google/Apple/Firebase and a fresh guest started, as on sign-out.
  /// Any failure before the server confirms leaves everything as it was.
  ///
  /// Pending store verifications (SharedPreferences) are deliberately kept:
  /// they belong to the store purchase, not to the account, and dropping one
  /// could miss Google Play's 3-day acknowledgement (an automatic refund).
  /// They verify again under the new guest.
  Future<DeleteAccountOutcome> deleteAccount() async {
    try {
      await _auth.prepareAccountDeletion();
    } on AuthException catch (e) {
      debugPrint('session: delete account stopped before the server (${e.kind.name})');
      return switch (e.kind) {
        AuthErrorKind.cancelled => DeleteAccountOutcome.cancelled,
        AuthErrorKind.network => DeleteAccountOutcome.offline,
        _ => DeleteAccountOutcome.failed,
      };
    }

    final api = ref.read(authApiProvider);
    var result = await api.deleteAccount();
    if (result.failure == ApiFailure.unauthorized) {
      // The JWT expired: re-mint it once and retry.
      await ensureBackendSession(force: true);
      result = await api.deleteAccount();
    }
    if (!result.isSuccess && !AuthApi.isAccountGone(result)) {
      debugPrint('session: delete account failed (${result.failure!.name}, ${result.statusCode})');
      return switch (result.failure!) {
        ApiFailure.offlineOrTransport || ApiFailure.timeout => DeleteAccountOutcome.offline,
        _ => DeleteAccountOutcome.failed,
      };
    }

    // The server account is gone. Wipe the device before the new guest gets
    // a session, so nothing in the outbox can reach the new account.
    await ref.read(progressRepositoryProvider).wipeForDeletedAccount();
    await ref.read(entitlementRepositoryProvider).clear();
    await ref.read(sessionStoreProvider).clear();
    _exchangedUid = null;
    try {
      await _auth.signOutToGuest();
      await ensureBackendSession(force: true);
    } on Object catch (e) {
      // Deleted all the same; the guest session is retried on the next launch
      // or from the Account screen.
      debugPrint('session: new guest after deletion failed ($e)');
    }
    return DeleteAccountOutcome.deleted;
  }

  Future<void> _afterAuth(Future<AuthIdentity> Function() action) async {
    await action(); // AuthException propagates to the UI
    await ensureBackendSession(force: true);
  }
}
