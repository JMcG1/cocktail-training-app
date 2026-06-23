import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/manager_team_tab.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('manager workflow smoke', () {
    testWidgets('team tab renders key manager states on a small phone', (
      tester,
    ) async {
      final controller = buildTestController(
        user: buildTestUser(role: UserRole.manager, name: 'Manager'),
      );
      await controller.initialize(usingFirebase: false);
      await controller.warmWorkspaceDataIfNeeded(force: true);

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManagerTeamTab(controller: controller)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Team dashboard'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);

      expect(
        find.text(
          'Live staff invites are not available in this build yet, but you can still review the training and sales data already loaded here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Team members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
