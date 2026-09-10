import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

/// HTTP implementation of [AuthRepository] against the Bsheel API.
///
/// Tokens are persisted through [ApiTokenStore]; the access token's `sub`
/// claim identifies the principal, and profile reads remain the source of
/// truth for anything displayed.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(
    this._client,
    this._tokenStore, {
    String googleIosClientId = '',
    String googleWebClientId = '',
  })  : _googleIosClientId = googleIosClientId,
        _googleWebClientId = googleWebClientId;

  final ApiClient _client;
  final ApiTokenStore _tokenStore;
  final String _googleIosClientId;
  final String _googleWebClientId;
  final StreamController<AuthState> _changes = StreamController.broadcast();
  Future<void>? _googleInitialization;
  AuthUser? _currentUser;

  /// Restores a locally persisted Nest session during application bootstrap.
  /// An expired access token is still restored: [ApiClient] performs serialized
  /// refresh-token rotation on the first authenticated request.
  Future<void> restoreSession() async {
    final tokens = await _tokenStore.read();
    if (tokens == null) return;
    try {
      _currentUser = _userFromAccessToken(tokens.accessToken);
      _changes.add(AuthState(AuthChangeEvent.initialSession, _session(tokens)));
    } catch (_) {
      await _tokenStore.clear();
      _currentUser = null;
      _changes.add(const AuthState(AuthChangeEvent.signedOut, null));
    }
  }

  @override
  Stream<AuthState> get authStateChanges => _changes.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthResult> signInWithEmail(String email, String password) async {
    final data = apiObject(
      await _client.post(
        'auth/login',
        authenticated: false,
        body: {'email': email.trim().toLowerCase(), 'password': password},
      ),
    );
    return _acceptTokens(ApiTokenPair.fromJson(data), AuthChangeEvent.signedIn);
  }

  @override
  Future<AuthResult> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  }) async {
    final username = (data?['username'] ?? '').toString().trim();
    final displayName = (data?['display_name'] ?? username).toString().trim();
    final response = apiObject(
      await _client.post(
        'auth/register',
        authenticated: false,
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'username': username,
          'displayName': displayName,
          'ageVerified': data?['age_verified'] == true,
        },
      ),
    );
    if (response['confirmationRequired'] == true) {
      return const AuthResult.pendingConfirmation();
    }
    return _acceptTokens(
      ApiTokenPair.fromJson(response),
      AuthChangeEvent.signedIn,
    );
  }

  @override
  Future<void> signOut() async {
    final tokens = await _tokenStore.read();
    if (tokens != null) {
      try {
        await _client
            .post('auth/logout', body: {'refreshToken': tokens.refreshToken});
      } on ApiException {
        // Local logout remains available when the server/session has expired.
      }
    }
    await _tokenStore.clear();
    _currentUser = null;
    _changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Future<void> resetPassword(String email) async {
    await _client.post(
      'auth/password-recovery',
      authenticated: false,
      body: {'email': email.trim().toLowerCase()},
    );
  }

  @override
  Future<void> resendSignupConfirmation(String email) async {
    await _client.post(
      'auth/email-confirmation/resend',
      authenticated: false,
      body: {'email': email.trim().toLowerCase()},
    );
  }

  /// Completes the new backend's one-time password recovery link.
  Future<void> completePasswordRecovery(
    String token,
    String newPassword,
  ) async {
    await _client.post(
      'auth/password-recovery/complete',
      authenticated: false,
      body: {'token': token, 'newPassword': newPassword},
    );
  }

  /// Completes the new backend's one-time email-confirmation link.
  Future<void> completeEmailConfirmation(String token) async {
    await _client.post(
      'auth/email-confirmation/complete',
      authenticated: false,
      body: {'token': token},
    );
  }

  @override
  Future<AuthUser> updatePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final data = apiObject(
      await _client.post(
        'auth/password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      ),
    );

    // The server bumped `token_version` and revoked every session — including
    // this one — so the tokens we hold are already dead. It returns a fresh
    // pair alongside the account, and storing it is what keeps this device
    // signed in rather than dropping the user on the login screen right after
    // they successfully changed their password.
    await _acceptTokens(ApiTokenPair.fromJson(data), AuthChangeEvent.userUpdated);

    return AuthUser(
      id: (data['id'] ?? _currentUser?.id ?? '').toString(),
      email: data['email']?.toString() ?? _currentUser?.email,
      userMetadata: _currentUser?.userMetadata ?? const {},
    );
  }

  @override
  Future<AuthResult> signInWithApple() async {
    final rawNonce = _nonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final idToken = credential.identityToken;
    if (idToken == null)
      throw const AuthException('Apple Sign In failed — no identity token.');
    final displayName = [credential.givenName, credential.familyName]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    return _oauth('apple', idToken, nonce: rawNonce, displayName: displayName);
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    final provider = GoogleSignIn.instance;
    _googleInitialization ??= provider.initialize(
      clientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
      serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
    );
    await _googleInitialization;
    try {
      await provider.signOut();
    } catch (_) {}
    final account = await provider.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null)
      throw const AuthException('Google Sign In failed — no ID token.');
    return _oauth('google', idToken, displayName: account.displayName ?? '');
  }

  @override
  Future<AuthResult> signInWithPhone(String phoneNumber, {String? email}) async {
    final start = apiObject(
      await _client.post(
        'auth/phone/start',
        authenticated: false,
        body: {
          'phoneNumber': phoneNumber,
          'ageVerified': true,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      ),
    );
    final handoff = await _completePhoneRedirect(
      start['authorizationUrl'] as String,
    );
    final data = apiObject(
      await _client.post(
        'auth/phone/complete',
        authenticated: false,
        body: {'handoffCode': handoff},
      ),
    );
    return _acceptTokens(ApiTokenPair.fromJson(data), AuthChangeEvent.signedIn);
  }

  @override
  Future<AuthResult> linkPhone(String phoneNumber) async {
    final start = apiObject(
      await _client.post(
        'auth/link/phone/start',
        body: {'phoneNumber': phoneNumber},
      ),
    );
    final handoff = await _completePhoneRedirect(
      start['authorizationUrl'] as String,
    );
    // The backend always re-issues a fresh token pair here, even though the
    // caller was already signed in: the OLD access token still carries
    // `phoneVerified: false`, and that claim is what the router's mandatory
    // verification gate reads. Accepting the new pair is what makes the
    // gate clear immediately instead of waiting for the next natural
    // refresh.
    final data = apiObject(
      await _client.post(
        'auth/phone/complete',
        authenticated: false,
        body: {'handoffCode': handoff},
      ),
    );
    return _acceptTokens(
        ApiTokenPair.fromJson(data), AuthChangeEvent.userUpdated);
  }

  /// Set only while a phone-sign-in redirect is in flight, resolved by
  /// [handlePhoneCallback] once the OS delivers the verified
  /// `https://admin.bsheel.app/phone-signin-callback` App Link/Universal
  /// Link back into the app (see RoutePaths.phoneSigninCallback). No custom
  /// URL scheme is used for this — those are not OS-verified and another
  /// app could register the same one to intercept an auth callback.
  Completer<Uri>? _pendingPhoneCallback;

  /// Called by the router the moment the verified callback link lands.
  /// A no-op if nothing is waiting (a stray or replayed link) — the
  /// backend's one-time handoff code is what actually secures the
  /// exchange; this only wakes up whichever call is waiting for it.
  void handlePhoneCallback(Uri uri) {
    _pendingPhoneCallback?.complete(uri);
    _pendingPhoneCallback = null;
  }

  Future<String> _completePhoneRedirect(String authorizationUrl) async {
    final completer = Completer<Uri>();
    _pendingPhoneCallback = completer;
    final launched = await launchUrl(
      Uri.parse(authorizationUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _pendingPhoneCallback = null;
      throw const AuthException('Could not open the phone verification page.');
    }
    final Uri result;
    try {
      // Matches the backend's own 5-minute state TTL (phone_signin_states).
      result = await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      _pendingPhoneCallback = null;
      throw const AuthException('Phone sign-in timed out.');
    }
    final handoff = result.queryParameters['handoff'];
    if (handoff == null || handoff.isEmpty) {
      throw const AuthException('Phone sign-in did not complete.');
    }
    return handoff;
  }

  Future<AuthResult> _oauth(
    String provider,
    String idToken, {
    String? nonce,
    String? displayName,
  }) async {
    final data = apiObject(
      await _client.post(
        'auth/oauth',
        authenticated: false,
        body: {
          'provider': provider,
          'idToken': idToken,
          if (nonce != null) 'nonce': nonce,
          if (displayName != null && displayName.trim().isNotEmpty)
            'displayName': displayName.trim(),
          'ageVerified': true,
        },
      ),
    );
    return _acceptTokens(ApiTokenPair.fromJson(data), AuthChangeEvent.signedIn);
  }

  Future<AuthResult> _acceptTokens(
    ApiTokenPair tokens,
    AuthChangeEvent event,
  ) async {
    await _tokenStore.write(tokens);
    _currentUser = _userFromAccessToken(tokens.accessToken);
    final session = _session(tokens);
    _changes.add(AuthState(event, session));
    return AuthResult(session: session);
  }

  AuthSession _session(ApiTokenPair tokens) => AuthSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: tokens.expiresIn)),
        user: _currentUser ?? _userFromAccessToken(tokens.accessToken),
      );


  AuthUser _userFromAccessToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException('Malformed access token');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map || payload['sub'] is! String) {
      throw const FormatException('Access token has no subject');
    }
    return AuthUser(
      id: payload['sub'] as String,
      email: payload['email']?.toString(),
      userMetadata: {
        if (payload['role'] != null) 'role': payload['role'],
        if (payload['username'] != null) 'username': payload['username'],
        if (payload['phoneVerified'] != null)
          'phoneVerified': payload['phoneVerified'],
      },
    );
  }

  String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  void dispose() => _changes.close();
}
