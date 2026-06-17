import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/study_mode_tab.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('study mode exposes extra revision decks and session focus flow', (
    tester,
  ) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.bartender, name: 'Bartender'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StudyModeTab(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Study mode'), findsOneWidget);
    expect(find.text('Guided'), findsWidgets);
    expect(find.text('Blind recall'), findsWidgets);
    expect(find.text('Rapid fire'), findsWidgets);
    expect(find.text('Weak spots'), findsWidgets);
    expect(find.text('Batch builds'), findsOneWidget);
    expect(find.text('Session focus'), findsWidgets);
    expect(find.text('Ingredient focus'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Reveal full build'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Mark needs work'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final sessionFocusChip = find.text('Session focus', skipOffstage: false).last;
    await tester.scrollUntilVisible(
      sessionFocusChip,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(sessionFocusChip, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.text('Marked for another pass in this study session.'),
      findsOneWidget,
    );
  });
}
