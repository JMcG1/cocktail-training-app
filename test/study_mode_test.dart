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
    expect(find.text('Study feedback'), findsOneWidget);
    expect(find.textContaining('Best next deck:'), findsOneWidget);
    expect(find.text('Open next deck'), findsOneWidget);

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
    await tester.tap(sessionFocusChip, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.text('Marked for another pass in this study session.'),
      findsOneWidget,
    );
  });

  testWidgets('study suggestions prioritise weak cocktails with higher sales exposure', (
    tester,
  ) async {
    final controller = buildTestController(
      user: buildTestUser(role: UserRole.owner, name: 'Jamie'),
    );
    await controller.initialize(usingFirebase: false);

    final session = controller.createWeeklySession(
      label: 'Specs focus',
      weekStart: DateTime(2026, 6, 15),
      concerns: const [
        StockConcernItem(ingredientName: 'Aperol'),
        StockConcernItem(ingredientName: 'Bacardi Superior'),
      ],
    );
    controller.saveBartenderSales(
      weekId: session.id,
      bartenderName: 'Jamie',
      entries: const [
        BartenderSalesEntry(
          cocktailId: 'aperol-spritz',
          cocktailName: 'Aperol Spritz',
          quantitySold: 20,
          salesValueGbp: 235,
        ),
        BartenderSalesEntry(
          cocktailId: 'classic-mojito',
          cocktailName: 'Classic Mojito',
          quantitySold: 2,
          salesValueGbp: 23.50,
        ),
      ],
    );

    final quiz = controller.generateStockQuiz(
      weekId: session.id,
      bartenderName: 'Jamie',
      focus: QuizFocus.specs,
    );
    final aperolQuestion = quiz.questions.firstWhere(
      (question) => question.cocktailId == 'aperol-spritz',
    );
    final mojitoQuestion = quiz.questions.firstWhere(
      (question) => question.cocktailId == 'classic-mojito',
    );

    String wrongAnswerFor(QuizQuestion question) {
      return question.options.firstWhere(
        (option) => option != question.correctAnswer,
      );
    }

    controller.submitQuizAttempt(
      sessionId: quiz.id,
      bartenderName: 'Jamie',
      answers: {
        for (final question in quiz.questions)
          question.id: question.id == aperolQuestion.id ||
                  question.id == mojitoQuestion.id
              ? wrongAnswerFor(question)
              : question.correctAnswer,
      },
    );

    final suggestions = controller.weakAreaRecipeSuggestions();
    final feedback = controller.buildStudyFeedbackSummary();

    expect(suggestions, isNotEmpty);
    expect(suggestions.first.id, 'aperol-spritz');
    expect(feedback.focusCocktails.first, 'Aperol Spritz');
  });
}
