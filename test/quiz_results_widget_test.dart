import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/variance_math.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/presentation/screens/quiz_tabs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('results dialog shows saved result and overpour cost summary', (
    tester,
  ) async {
    final attempt = QuizAttempt(
      id: 'attempt-1',
      sessionId: 'session-1',
      bartenderName: 'Bartender',
      submittedAt: DateTime(2026, 6, 22, 12),
      scorePercent: 70,
      responses: [
        QuestionResponse(
          question: QuizQuestion(
            id: 'question-1',
            cocktailId: 'aperol-spritz',
            cocktailName: 'Aperol Spritz',
            prompt: 'How much Aperol goes into an Aperol Spritz?',
            options: const ['50ml', '75ml', '100ml'],
            correctAnswer: '50ml',
            explanation: 'The approved spec uses 50ml of Aperol.',
            kind: QuestionKind.ingredientMeasure,
            ingredientName: 'Aperol',
            correctMeasureMl: 50,
          ),
          selectedAnswer: '75ml',
          isCorrect: false,
          quantitySold: 30,
          deltaMl: 25,
        ),
      ],
      overpourLines: const [
        VarianceLine(
          ingredientName: 'Aperol',
          totalMl: 750,
          approximateValue: 30,
          direction: VarianceDirection.overpour,
        ),
      ],
      underpourLines: const [],
      coachingAreas: const ['Aperol Spritz'],
      encouragement: 'A quick review of specs would help.',
    );

    final summary = QuizSalesImpactSummary(
      lines: [
        QuizSalesImpactLine(
          cocktailId: 'aperol-spritz',
          cocktailName: 'Aperol Spritz',
          ingredientName: 'Aperol',
          direction: VarianceDirection.overpour,
          quantitySold: 30,
          exposureSalesValueGbp: 360,
          errorMlPerServe: 25,
          totalErrorMl: 750,
          ingredientCostImpactGbp: 30,
          recoverableCocktails: 15,
          recoverableRevenueGbp: 180,
        ),
      ],
      totalExposureCocktails: 30,
      totalExposureSalesValueGbp: 360,
      totalIngredientCostImpactGbp: 30,
      totalRecoverableCocktails: 15,
      totalRecoverableRevenueGbp: 180,
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    unawaited(showQuizResultsDialog(navigatorKey.currentContext!, attempt, summary));
    await tester.pumpAndSettle();

    expect(find.text('Results ready'), findsOneWidget);
    expect(find.textContaining('Potential overpour stock cost: £30.00'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
