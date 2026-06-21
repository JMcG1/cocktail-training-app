import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';
import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manager workspace keeps team tools and invites', (tester) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.manager, name: 'Manager'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(home: ManagerWorkspace(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cocktail Training - Library'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Study'), findsWidgets);
    expect(find.text('Quiz'), findsWidgets);
    expect(find.text('Progress'), findsWidgets);
    expect(find.text('Team'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
