import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/library_progress_tabs.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manager library shows approved cocktail prices', (tester) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.manager, name: 'Manager'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManagerLibraryTab(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Approved cocktail library'), findsOneWidget);
    expect(find.text('Aperol Spritz'), findsWidgets);
    expect(find.text('£11.75'), findsWidgets);
  });
}
