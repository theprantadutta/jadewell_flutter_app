/// The signed-in identity as the app sees it (no Firebase types leak out).
class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    required this.isAnonymous,
    required this.providers,
    this.email,
  });

  final String uid;
  final bool isAnonymous;

  /// e.g. `google.com`, `apple.com`, `password`.
  final List<String> providers;
  final String? email;
}

/// Why a sign-in/link attempt didn't succeed, for user-facing messages.
enum AuthErrorKind {
  cancelled,
  credentialInUse,
  emailInUse,
  invalidCredentials,
  weakPassword,
  invalidEmail,
  network,
  unsupported,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.kind, [this.code]);
  final AuthErrorKind kind;
  final String? code;

  @override
  String toString() => 'AuthException(${kind.name}, $code)';
}

/// Firebase-backed sign-in (snake-classic flow): everyone starts as an
/// anonymous guest; Google, Apple and email/password are *linked* to that
/// guest so progress is kept. Implementations live in `*_impl.dart`.
abstract interface class AuthService {
  AuthIdentity? get current;
  Stream<AuthIdentity?> get changes;

  /// Signs in anonymously unless someone is already signed in.
  Future<AuthIdentity> ensureSignedIn();

  /// Fresh Firebase ID token for the backend exchange.
  Future<String?> idToken({bool forceRefresh = false});

  Future<AuthIdentity> linkGoogle();
  Future<AuthIdentity> linkApple();
  Future<AuthIdentity> linkEmailPassword({required String email, required String password});

  /// Sign in to an existing account (replaces the guest; used on a new device).
  Future<AuthIdentity> signInWithGoogle();
  Future<AuthIdentity> signInWithApple();
  Future<AuthIdentity> signInWithEmailPassword({required String email, required String password});

  Future<void> sendPasswordReset(String email);

  /// Signs out and immediately starts a fresh guest session.
  Future<AuthIdentity> signOutToGuest();
}
