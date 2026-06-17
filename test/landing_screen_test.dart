import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('landing screen shows Cocktail Training login flow', (
    tester,
  ) async {
    final controller = buildTestController();
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(
        home: LandingScreen(controller: controller, onOpenTraining: () {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Cocktail Training'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Forgot password? Send reset link'), findsOneWidget);
    expect(find.text('Approved learning library'), findsOneWidget);
  });
}
