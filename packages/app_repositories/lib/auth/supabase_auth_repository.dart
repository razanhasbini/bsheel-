import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'auth_repository.dart';
import 'fcm_cleanup_stub.dart'
    if (dart.library.io) 'fcm_cleanup_native.dart';

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _client;
  /// Google OAuth client IDs injected at construction so they are never
  /// hardcoded in source. Pass values from Env.googleIosClientId /
  /// Env.googleWebClientId (dart-define at build time).
  final String _googleIosClientId;
  final String _googleWebClientId;

  SupabaseAuthRepository(
    this._client, {
    String googleIosClientId = '',
    String googleWebClientId = '',
  })  : _googleIosClientId = googleIosClientId,
        _googleWebClientId = googleWebClientId;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signInWithEmail(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  }) {
    return _client.auth.signUp(email: email, password: password, data: data);
  }

  @override
  Future<void> signOut() async {
    // Drop the device's FCM token BEFORE the auth session ends so
    // auth.uid() is still valid for the RPC; otherwise the device
    // keeps receiving pushes for this account after logout.
    try {
      await _client.rpc(RpcNames.deleteOwnFcmToken);
    } catch (e) {
      AppLogger.warning('[Auth] Failed to delete server FCM token: $e');
    }
    try {
      await deleteLocalFcmToken();
    } catch (e) {
      AppLogger.warning('[Auth] Failed to delete local FCM token: $e');
    }
    await _client.auth.signOut();
  }

  @override
  Future<void> resetPassword(String email) {
    // The Universal Link variant from SEC-024 was reverted: AASA at
    // admin.bsheel.app only allowlists /post, /user, /join,
    // Runner.entitlements has no associated-domains, and the admin
    // web has no /reset-password route — so emails were landing on a
    // blank page (Supabase fell back to its project Site URL =
    // localhost:3000). Custom scheme is the only working path until
    // Universal Links are properly wired (TODO: add /reset-password
    // to the AASA paths array, set associated-domains in the
    // Runner.entitlements, and add a /reset-password GoRoute to
    // admin_web that hands off to the mobile app).
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'https://admin.bsheel.app/reset-password',
    );
  }

  @override
  Future<void> resendSignupConfirmation(String email) {
    return _client.auth.resend(type: OtpType.signup, email: email);
  }

  @override
  Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<AuthResponse> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple Sign In failed — no identity token.');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    // Client IDs are injected at build time via --dart-define so they
    // can be rotated without a code change. See Env class in the mobile app.
    // Falls back to empty strings (sign-in will throw) if not configured.
    final iosClientId = _googleIosClientId;
    final webClientId = _googleWebClientId;

    final googleSignIn = GoogleSignIn(
      clientId: iosClientId.isNotEmpty ? iosClientId : null,
      serverClientId: webClientId.isNotEmpty ? webClientId : null,
    );

    // Clear any cached session to avoid stale token issues
    try {
      await googleSignIn.signOut();
    } catch (_) {
      // Not critical — proceed with sign-in even if clearing cache fails
    }

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw const AuthException('Google Sign In was cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw const AuthException('Google Sign In failed — no ID token.');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  @override
  User? get currentUser => _client.auth.currentUser;
}
