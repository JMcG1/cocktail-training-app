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
    await tester.pumpAndSettle();

    expect(find.text('Cocktail Training - Library'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Study'), findsWidgets);
    expect(find.text('Quiz'), findsWidgets);
    expect(find.text('Progress'), findsWidgets);
    expect(find.text('Team'), findsWidgets);
  });

  testWidgets('controller builds bartender exposure summaries', (tester) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.owner, name: 'Jamie'),
    );
    await controller.initialize(usingFirebase: false);

    final session = controller.createWeeklySession(
      label: 'Spritz focus',
      weekStart: DateTime(2026, 6, 15),
      concerns: const [StockConcernItem(ingredientName: 'Aperol')],
    );
    controller.saveBartenderSales(
      weekId: session.id,
      bartenderName: 'Jamie',
      entries: const [
        BartenderSalesEntry(
          cocktailId: 'aperol-spritz',
          cocktailName: 'Aperol Spritz',
          quantitySold: 12,
          salesValueGbp: 141,
        ),
        BartenderSalesEntry(
          cocktailId: 'classic-mojito',
          cocktailName: 'Classic Mojito',
          quantitySold: 4,
          salesValueGbp: 47,
        ),
      ],
    );

    final summaries = controller.buildBartenderExposureSummaries();

    expect(summaries, hasLength(1));
    expect(summaries.single.bartenderName, 'Jamie');
    expect(summaries.single.totalCocktailsSold, 16);
    expect(summaries.single.totalSalesValueGbp, 188);
    expect(summaries.single.topCocktails.first, 'Aperol Spritz · 12');
  });
}
