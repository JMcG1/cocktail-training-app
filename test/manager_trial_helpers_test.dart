import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/manager_trial_helpers.dart';
import 'package:stock_variance_coach/domain/models/models.dart';

void main() {
  RecipeImportDraft buildDraft({
    required String id,
    required String name,
    required String category,
    List<String> reviewFlags = const [],
    RecipeDraftStatus status = RecipeDraftStatus.pending,
  }) {
    return RecipeImportDraft(
      id: id,
      sourceLabel: 'ocr.txt',
      pageLabel: 'Page 1',
      name: name,
      category: category,
      glassware: 'Coupe',
      garnish: 'Orange twist',
      method: 'Shake',
      notes: '',
      ingredients: const [
        RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
      ],
      reviewFlags: reviewFlags,
      status: status,
      wasManuallyReviewed: status != RecipeDraftStatus.pending,
    );
  }

  group('Recipe review filtering and counts', () {
    final drafts = [
      buildDraft(
        id: '1',
        name: 'Approved Spritz',
        category: 'Spritz',
        status: RecipeDraftStatus.approved,
      ),
      buildDraft(
        id: '2',
        name: 'Review Martini',
        category: 'Martinis',
        reviewFlags: const ['Method needs review'],
      ),
      buildDraft(
        id: '3',
        name: 'APERNOL SPRITZ',
        category: 'Spritz',
        reviewFlags: const ['Possible OCR issue in the cocktail name.'],
      ),
      buildDraft(
        id: '4',
        name: 'Ignored Draft',
        category: 'Spritz',
        status: RecipeDraftStatus.deleted,
      ),
    ];

    test('filters by query, confidence, and category', () {
      final filtered = ManagerTrialHelpers.filterDrafts(
        drafts: drafts,
        query: 'spritz',
        confidence: RecipeConfidence.possibleOcrIssue,
        category: 'Spritz',
      );

      expect(filtered.map((item) => item.name), ['APERNOL SPRITZ']);
    });

    test('counts statuses and review confidence buckets', () {
      final counts = ManagerTrialHelpers.countDrafts(drafts);

      expect(counts.approved, 1);
      expect(counts.needsReview, 1);
      expect(counts.possibleOcrIssue, 1);
      expect(counts.deleted, 1);
    });
  });

  group('Sales validation', () {
    final session = WeeklyConcernSession(
      id: 'week-1',
      label: 'Monday focus',
      weekStart: sampleDate,
      concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      targetCocktailIds: const ['recipe-1'],
      bartenderSales: const [
        BartenderWeeklySales(
          bartenderName: 'Jamie',
          entries: [
            BartenderSalesEntry(
              cocktailId: 'recipe-1',
              cocktailName: 'Approved Sour',
              quantitySold: 12,
            ),
          ],
        ),
      ],
      quizSessionIds: [],
    );

    test('rejects duplicate bartender names', () {
      final result = ManagerTrialHelpers.validateBartenderSales(
        session: session,
        bartenderName: 'jamie',
        rawQuantitiesByCocktailId: const {'recipe-1': '6'},
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('already has sales saved'));
    });

    test('rejects invalid sales quantities', () {
      final result = ManagerTrialHelpers.validateBartenderSales(
        session: session,
        bartenderName: 'Sarah',
        rawQuantitiesByCocktailId: const {'recipe-1': '-2'},
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('whole numbers'));
    });
  });

  group('Workflow readiness and wording', () {
    test('builds stock workflow readiness from saved session data', () {
      final session = WeeklyConcernSession(
        id: 'week-2',
        label: 'Monday focus',
        weekStart: sampleDate,
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
        targetCocktailIds: const ['recipe-1'],
        bartenderSales: const [
          BartenderWeeklySales(
            bartenderName: 'Jamie',
            entries: [
              BartenderSalesEntry(
                cocktailId: 'recipe-1',
                cocktailName: 'Approved Sour',
                quantitySold: 4,
              ),
            ],
          ),
        ],
        quizSessionIds: const ['quiz-1'],
      );
      final quizSession = QuizSession(
        id: 'quiz-1',
        title: 'Targeted quiz',
        bartenderName: 'Jamie',
        kind: QuizKind.stockVariance,
        isActive: true,
        createdAt: sampleDate,
        questions: const [],
        weekId: 'week-2',
      );
      final attempt = QuizAttempt(
        id: 'attempt-1',
        sessionId: 'quiz-1',
        bartenderName: 'Jamie',
        submittedAt: sampleDate,
        scorePercent: 90,
        responses: const [],
        overpourLines: const [],
        underpourLines: const [],
        coachingAreas: const [],
        encouragement: 'Nice work',
        weekId: 'week-2',
      );

      final progress = ManagerTrialHelpers.buildStockWorkflowProgress(
        session: session,
        quizSessions: [quizSession],
        quizAttempts: [attempt],
      );

      expect(progress.concernsSelected, isTrue);
      expect(progress.cocktailsReviewed, isTrue);
      expect(progress.salesEntered, isTrue);
      expect(progress.quizLaunched, isTrue);
      expect(progress.resultsAvailable, isTrue);
    });

    test('dashboard wording helper blocks blame language', () {
      expect(
        ManagerTrialHelpers.wordingIsSupportive(
          'Potential variance and training focus are ready for review.',
        ),
        isTrue,
      );
      expect(
        ManagerTrialHelpers.wordingIsSupportive(
          'You lost stock and caused a problem.',
        ),
        isFalse,
      );
    });
  });
}

final sampleDate = DateTime(2026, 1, 1);
