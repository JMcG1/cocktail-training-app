import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

import 'test_app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner settings show ingredient pricing queue metrics', (
    tester,
  ) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.owner, name: 'Owner'),
    );
    await controller.initialize(usingFirebase: false);
    await controller.saveIngredient(
      name: 'Vodka',
      bottleSizeMl: 700,
      bottleCost: 28,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(controller: controller, isOnline: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ingredient costs'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Ingredient costs'), findsOneWidget);
    expect(find.text('Missing bottle size'), findsWidgets);
    expect(find.text('Missing bottle price'), findsWidgets);
    expect(find.text('Garnish'), findsWidgets);
    expect(find.text('Needs pricing'), findsOneWidget);
    expect(find.text('Batch cost summary'), findsOneWidget);
  });

  testWidgets('batch costs are derived from ingredient pricing', (
    tester,
  ) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.owner, name: 'Owner'),
    );
    await controller.initialize(usingFirebase: false);
    await controller.saveIngredient(
      name: 'Vodka',
      bottleSizeMl: 1000,
      bottleCost: 20,
    );
    await controller.saveIngredient(
      name: 'Lime Juice',
      bottleSizeMl: 1000,
      bottleCost: 8,
    );
    controller.saveBatch(
      const BatchRecipe(
        id: 'house-batch',
        name: 'House Batch',
        category: 'Batch Recipes',
        notes: '',
        ingredients: [
          RecipeIngredient(ingredientName: 'Vodka', measureMl: 500),
          RecipeIngredient(ingredientName: 'Lime Juice', measureMl: 500),
        ],
        totalBatchVolumeMl: 1000,
        sourceLabel: 'test',
        needsReview: false,
        reviewFlags: [],
        isApproved: true,
        wasManuallyReviewed: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(controller: controller, isOnline: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Batch cost summary'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('House Batch'), findsOneWidget);
    expect(find.text('Calculated batch cost: £14.00'), findsOneWidget);
    expect(find.text('Batch cost per ml: £0.0140/ml'), findsOneWidget);
  });
}
