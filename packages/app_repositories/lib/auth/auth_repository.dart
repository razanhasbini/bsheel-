import 'auth_models.dart';

/// Authentication contract consumed by both applications.
abstract class AuthRepository {
  /// Session lifecycle events. Emits on restore, sign-in, refresh,
  /// sign-out and password recovery.
  Stream<AuthState> get authStateChanges;

  /// The signed-in principal, or null when there is no session.
  AuthUser? get currentUser;

  Future<AuthResult> signInWithEmail(String email, String password);

  /// Creates a password account. Returns
  /// [AuthResult.confirmationRequired] when the deployment requires the
  /// user to confirm their email before a session is issued.
  ///
  /// Throws [AuthException] with code `EMAIL_TAKEN` or `USERNAME_TAKEN`
  /// when the address or username is already in use.
  Future<AuthResult> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  });

  Future<void> signOut();

  /// Starts password recovery. Succeeds identically for unknown addresses
  /// so the response cannot be used to enumerate accounts.
  Future<void> resetPassword(String email);

  /// Re-send the signup confirmation email for an unconfirmed account.
  Future<void> resendSignupConfirmation(String email);

  /// Sets a new password for the active session, re-authenticating first.
  ///
  /// [currentPassword] is required by the API: without it, anyone holding an
  /// access token could take the account over permanently. The server revokes
  /// every session and returns a fresh token pair, which the implementation
  /// stores so this device stays signed in.
  Future<AuthUser> updatePassword(String currentPassword, String newPassword);

  Future<AuthResult> signInWithApple();

  Future<AuthResult> signInWithGoogle();
}
