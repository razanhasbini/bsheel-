import 'package:admin_web/features/admin_auth/presentation/pages/confirm_email_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rejects a missing confirmation token without exposing details',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ConfirmEmailPage(token: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not confirm email.'), findsOneWidget);
    expect(
      find.text('This confirmation link is invalid or has expired.'),
      findsOneWidget,
    );
    expect(find.textContaining('token='), findsNothing);
  });
}
