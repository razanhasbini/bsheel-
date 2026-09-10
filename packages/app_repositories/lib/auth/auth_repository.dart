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

  /// Signs in (or signs up, for a first-time number) via CAMARA Number
  /// Verification: opens the carrier consent redirect in the system
  /// browser, waits for it to complete, and exchanges the result for a
  /// session. Throws [AuthException] if the user cancels or the network
  /// cannot verify the number.
  /// [phoneNumber] must be E.164 (`+96170123456`). It is only a CLAIM: the
  /// backend hands it to CAMARA Number Verification V1, and the mobile
  /// network decides whether this device is actually using it. A mismatch
  /// throws `PHONE_NUMBER_NOT_VERIFIED`, never a signed-in session.
  Future<AuthResult> signInWithPhone(String phoneNumber, {String? email});

  /// Same redirect, but attaches the verified number to the already
  /// signed-in account instead of creating a session. Still returns an
  /// [AuthResult]: the backend re-issues a fresh token pair carrying
  /// `phoneVerified: true`, which the caller must accept the same way as
  /// any other sign-in for the mandatory-verification gate to clear.
  Future<AuthResult> linkPhone(String phoneNumber);

  /// Called by the router when the verified
  /// `https://admin.bsheel.app/phone-signin-callback` deep link lands,
  /// resolving whichever [signInWithPhone] or [linkPhone] call is waiting
  /// for it. A no-op if nothing is waiting.
  void handlePhoneCallback(Uri uri);
}
