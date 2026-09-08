import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_app/app.dart';
import 'package:mobile_app/core/providers/auth_repository_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream<AuthState>.empty();

  @override
  AuthUser? get currentUser => null;

  @override
  Future<AuthResult> signInWithEmail(String email, String password) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() {
    throw UnimplementedError();
  }

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> resendSignupConfirmation(String email) async {}

  @override
  Future<AuthUser> updatePassword(String newPassword) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> signInWithApple() {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> signInWithGoogle() {
    throw UnimplementedError();
  }
}

void main() {
  final authRepository = _FakeAuthRepository();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
        ],
        child: const QuestApp(),
      ),
    );
    await tester.pump();
    // Advance past splash/navigation timers so none are pending at teardown.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
  });
}
