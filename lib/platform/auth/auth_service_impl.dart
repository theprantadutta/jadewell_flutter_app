import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Firebase Auth + Google Sign-In v7 + Apple via firebase_auth's native provider.
class FirebaseAuthServiceImpl implements AuthService {
  FirebaseAuthServiceImpl({required String? googleWebClientId})
      : _googleReady = GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Future<void> _googleReady;

  static AuthIdentity? _map(User? u) => u == null
      ? null
      : AuthIdentity(
          uid: u.uid,
          isAnonymous: u.isAnonymous,
          email: u.email,
          providers: [for (final p in u.providerData) p.providerId],
        );

  @override
  AuthIdentity? get current => _map(_auth.currentUser);

  @override
  Stream<AuthIdentity?> get changes => _auth.userChanges().map(_map);

  @override
  Future<AuthIdentity> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return _map(existing)!;
    return _guard(() async => (await _auth.signInAnonymously()).user);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);

  // ---- linking (keeps the guest's uid, so all progress stays) ----

  @override
  Future<AuthIdentity> linkGoogle() => _guard(() async {
        final user = await _requireAnonymous();
        return (await user.linkWithCredential(await _googleCredential())).user;
      });

  @override
  Future<AuthIdentity> linkApple() => _guard(() async {
        final user = await _requireAnonymous();
        return (await user.linkWithProvider(_appleProvider())).user;
      });

  @override
  Future<AuthIdentity> linkEmailPassword({required String email, required String password}) => _guard(() async {
        final user = await _requireAnonymous();
        final result = await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: password));
        unawaited(result.user?.sendEmailVerification().catchError((Object _) {}));
        return result.user;
      });

  // ---- signing in to an existing account ----

  @override
  Future<AuthIdentity> signInWithGoogle() =>
      _guard(() async => (await _auth.signInWithCredential(await _googleCredential())).user);

  @override
  Future<AuthIdentity> signInWithApple() => _guard(() async => (await _auth.signInWithProvider(_appleProvider())).user);

  @override
  Future<AuthIdentity> signInWithEmailPassword({required String email, required String password}) =>
      _guard(() async => (await _auth.signInWithEmailAndPassword(email: email, password: password)).user);

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_kind(e.code), e.code);
    }
  }

  @override
  Future<AuthIdentity> signOutToGuest() async {
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // not signed in with Google
    }
    await _auth.signOut();
    return ensureSignedIn();
  }

  @override
  Future<void> prepareAccountDeletion() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // AdditionalUserInfo.authorizationCode is only filled by the native
    // Apple flow on iOS; Android never offers Sign in with Apple.
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (!user.providerData.any((p) => p.providerId == 'apple.com')) return;
    try {
      final credential = await user.reauthenticateWithProvider(_appleProvider());
      final code = credential.additionalUserInfo?.authorizationCode;
      if (code == null || code.isEmpty) throw const AuthException(AuthErrorKind.unknown, 'no-authorization-code');
      await _auth.revokeTokenWithAuthorizationCode(code);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_kind(e.code), e.code);
    }
  }

  // ---- helpers ----

  Future<User> _requireAnonymous() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    if (!user.isAnonymous) throw const AuthException(AuthErrorKind.credentialInUse, 'already-linked');
    return user;
  }

  Future<AuthCredential> _googleCredential() async {
    await _googleReady;
    final google = GoogleSignIn.instance;
    if (!google.supportsAuthenticate()) throw const AuthException(AuthErrorKind.unsupported);
    try {
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthException(AuthErrorKind.unknown, 'no-id-token');
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      throw AuthException(
        e.code == GoogleSignInExceptionCode.canceled ? AuthErrorKind.cancelled : AuthErrorKind.unknown,
        e.code.name,
      );
    }
  }

  static AppleAuthProvider _appleProvider() => AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');

  Future<AuthIdentity> _guard(Future<User?> Function() action) async {
    try {
      final user = await action();
      if (user == null) throw const AuthException(AuthErrorKind.unknown, 'no-user');
      return _map(user)!;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_kind(e.code), e.code);
    }
  }

  static AuthErrorKind _kind(String code) => switch (code) {
        'canceled' || 'user-cancelled' || 'web-context-canceled' => AuthErrorKind.cancelled,
        'credential-already-in-use' || 'provider-already-linked' => AuthErrorKind.credentialInUse,
        'email-already-in-use' => AuthErrorKind.emailInUse,
        'wrong-password' || 'invalid-credential' || 'user-not-found' || 'invalid-login-credentials' =>
          AuthErrorKind.invalidCredentials,
        'weak-password' => AuthErrorKind.weakPassword,
        'invalid-email' => AuthErrorKind.invalidEmail,
        'network-request-failed' => AuthErrorKind.network,
        'operation-not-allowed' => AuthErrorKind.unsupported,
        _ => AuthErrorKind.unknown,
      };
}
