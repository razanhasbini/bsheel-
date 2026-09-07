import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRepository {
  Stream<AuthState> get authStateChanges;
  Future<AuthResponse> signInWithEmail(String email, String password);
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  });
  Future<void> signOut();
  Future<void> resetPassword(String email);

  /// Re-send the signup confirmation email for an unconfirmed account.
  Future<void> resendSignupConfirmation(String email);

  Future<UserResponse> updatePassword(String newPassword);
  Future<AuthResponse> signInWithApple();
  Future<AuthResponse> signInWithGoogle();
  User? get currentUser;
}
