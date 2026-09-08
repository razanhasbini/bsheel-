/// Authentication domain types.
///
/// These are deliberately plain Dart: the app's auth contract must not be
/// shaped by whichever client library happens to talk to the API. Member
/// names match what the UI already reads so call sites stay stable.
library;

/// Lifecycle events emitted by [AuthRepository.authStateChanges].
enum AuthChangeEvent {
  /// A persisted session was restored during bootstrap.
  initialSession,

  /// A session was established by an explicit sign-in.
  signedIn,

  /// The session ended, by sign-out or by an unrecoverable refresh failure.
  signedOut,

  /// The access token was rotated; the user is unchanged.
  tokenRefreshed,

  /// Profile or credential data changed for the signed-in user.
  userUpdated,

  /// A password-recovery link was consumed and a recovery session is active.
  passwordRecovery,
}

/// The authenticated principal.
class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.userMetadata = const {},
  });

  final String id;
  final String? email;

  /// Non-authoritative claims carried on the access token (username,
  /// display name, role). Profile reads remain the source of truth.
  final Map<String, dynamic> userMetadata;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'AuthUser($id)';
}

/// A live session: the tokens plus the principal they authenticate.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.user,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final AuthUser user;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && DateTime.now().isAfter(expiry);
  }
}

/// One emission of the auth lifecycle stream.
class AuthState {
  const AuthState(this.event, this.session);

  final AuthChangeEvent event;

  /// Null for [AuthChangeEvent.signedOut].
  final AuthSession? session;

  AuthUser? get user => session?.user;

  @override
  String toString() => 'AuthState($event, hasSession=${session != null})';
}

/// The outcome of a sign-in or sign-up attempt.
class AuthResult {
  const AuthResult({
    this.session,
    this.confirmationRequired = false,
  });

  /// Signup that requires an email confirmation before a session exists.
  const AuthResult.pendingConfirmation()
      : session = null,
        confirmationRequired = true;

  final AuthSession? session;

  /// True when the account was created but cannot sign in until the
  /// confirmation email is used.
  final bool confirmationRequired;

  AuthUser? get user => session?.user;
}

/// Raised for authentication failures.
///
/// [toString] intentionally renders as `AuthException: <message>` because the
/// UI's error mapper matches on that prefix.
class AuthException implements Exception {
  const AuthException(this.message, {this.code});

  final String message;

  /// Stable machine-readable code from the API, e.g. `EMAIL_TAKEN`.
  final String? code;

  @override
  String toString() => 'AuthException: $message';
}
