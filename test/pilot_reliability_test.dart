import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/manager_trial_helpers.dart';
import 'package:stock_variance_coach/core/utils/weekly_workflow_draft.dart';
import 'package:stock_variance_coach/data/firestore/firestore_serializers.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  group('Operational reliability', () {
    test('prevents duplicate stock sessions for the same weekly concern setup', () {
      final repository = LocalTrainingRepository();
      repository.saveImportedDrafts([
        _approvedDraft(
          id: 'recipe-1',
          name: 'Approved Sour',
          ingredient: 'Vodka',
        ),
      ]);

      final first = repository.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 13),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      final second = repository.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 13),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );

      expect(first.id, second.id);
      expect(repository.weeklySessions.length, 1);
    });

    test('prevents duplicate quiz submissions for the same session and bartender', () {
      final repository = LocalTrainingRepository();
      repository.saveImportedDrafts([
        _approvedDraft(
          id: 'recipe-2',
          name: 'Approved Martini',
          ingredient: 'Vodka',
        ),
      ]);
      final week = repository.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 13),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      repository.saveBartenderSales(
        weekId: week.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'recipe-2',
            cocktailName: 'Approved Martini',
            quantitySold: 8,
          ),
        ],
      );
      final quiz = repository.generateStockQuizSession(
        weekId: week.id,
        bartenderName: 'Jamie',
      );
      final answers = {
        for (final question in quiz.questions) question.id: question.correctAnswer,
      };

      final first = repository.submitQuizAttempt(
        sessionId: quiz.id,
        bartenderName: 'Jamie',
        answers: answers,
      );
      final second = repository.submitQuizAttempt(
        sessionId: quiz.id,
        bartenderName: 'Jamie',
        answers: answers,
      );

      expect(first.id, second.id);
      expect(repository.quizAttempts.length, 1);
    });

    test('practice quiz generation avoids duplicate prompts and answer choices', () {
      final repository = LocalTrainingRepository();
      repository.saveImportedDrafts([
        _approvedDraft(
          id: 'recipe-3',
          name: 'Approved Spritz',
          ingredient: 'Vodka',
          garnish: 'Orange slice',
          glassware: 'Wine glass',
          method: 'Build over ice',
        ),
        _approvedDraft(
          id: 'recipe-4',
          name: 'Approved Highball',
          ingredient: 'Gin',
          garnish: 'Lime wedge',
          glassware: 'Highball',
          method: 'Build over ice',
        ),
      ]);

      final quiz = repository.generatePracticeQuizSession(bartenderName: 'Training user');
      final prompts = quiz.questions.map((question) => question.prompt).toList();

      expect(prompts.toSet().length, prompts.length);
      for (final question in quiz.questions) {
        expect(question.options.toSet().length, question.options.length);
      }
    });
  });

  group('Autosave and degraded handling', () {
    test('weekly workflow draft round trips for autosave recovery', () {
      const draft = WeeklyWorkflowDraft(
        selectedWeekId: 'week-1',
        selectedConcerns: {'Vodka': true},
        shortValues: {'Vodka': '250'},
        impactValues: {'Vodka': '8.50'},
        noteValues: {'Vodka': 'Worth revisiting martini builds'},
        bartenderName: 'Jamie',
        salesValues: {'week-1-recipe-1': '12'},
      );

      final restored = WeeklyWorkflowDraft.fromJson(draft.toJson());

      expect(restored.selectedWeekId, 'week-1');
      expect(restored.selectedConcerns['Vodka'], isTrue);
      expect(restored.salesValues['week-1-recipe-1'], '12');
      expect(restored.hasUnsavedProgress, isTrue);
    });

    test('empty workflow draft reports no unsaved progress', () {
      expect(WeeklyWorkflowDraft.empty().hasUnsavedProgress, isFalse);
    });

    test('public quiz route helper supports query and deep-link path refreshes', () {
      expect(
        sessionIdFromUri(Uri.parse('https://example.com/quiz/quiz-123')),
        'quiz-123',
      );
      expect(
        sessionIdFromUri(Uri.parse('https://example.com/?session=quiz-456')),
        'quiz-456',
      );
    });
  });

  group('Dashboard trends and resilience', () {
    test('dashboard exposes trend summaries, session counts, and supportive wording', () async {
      final controller = AppController(
        authRepository: _FakeAuthRepository(),
        trainingRepository: LocalTrainingRepository(),
        environment: _environment,
      );
      await controller.initialize();

      controller.saveImportedDrafts([
        _approvedDraft(
          id: 'recipe-5',
          name: 'Approved Sour',
          ingredient: 'Vodka',
          garnish: 'Orange twist',
          glassware: 'Coupe',
          method: 'Shake and fine strain',
        ),
      ]);
      final weekOne = controller.createWeeklySession(
        label: 'Week one',
        weekStart: DateTime(2026, 5, 6),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      controller.saveBartenderSales(
        weekId: weekOne.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'recipe-5',
            cocktailName: 'Approved Sour',
            quantitySold: 6,
          ),
        ],
      );
      final weekOneQuiz = controller.generateStockQuiz(
        weekId: weekOne.id,
        bartenderName: 'Jamie',
      );
      controller.submitQuizAttempt(
        sessionId: weekOneQuiz.id,
        bartenderName: 'Jamie',
        answers: {
          for (final question in weekOneQuiz.questions)
            question.id: question.correctAnswer,
        },
      );

      final weekTwo = controller.createWeeklySession(
        label: 'Week two',
        weekStart: DateTime(2026, 5, 13),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      controller.saveBartenderSales(
        weekId: weekTwo.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'recipe-5',
            cocktailName: 'Approved Sour',
            quantitySold: 6,
          ),
        ],
      );
      final weekTwoQuiz = controller.generateStockQuiz(
        weekId: weekTwo.id,
        bartenderName: 'Jamie',
      );
      final answers = <String, String>{};
      for (var index = 0; index < weekTwoQuiz.questions.length; index += 1) {
        final question = weekTwoQuiz.questions[index];
        answers[question.id] = index == 0 && question.options.length > 1
            ? question.options.last
            : question.correctAnswer;
      }
      controller.submitQuizAttempt(
        sessionId: weekTwoQuiz.id,
        bartenderName: 'Jamie',
        answers: answers,
      );

      final dashboard = controller.buildDashboard();

      expect(dashboard.weeklyConfidence.length, greaterThanOrEqualTo(2));
      expect(dashboard.bartenderAverageScores['Jamie'], isNotNull);
      expect(dashboard.closedQuizSessions, greaterThanOrEqualTo(2));
      expect(
        ManagerTrialHelpers.wordingIsSupportive(
          'Potential variance and training focus are ready for review.',
        ),
        isTrue,
      );
    });

    test('serializers handle partial data gracefully', () {
      final session = FirestoreSerializers.quizSessionFromMap(
        'quiz-1',
        const {
          'title': 'Quiz',
          'questions': [
            {'id': 'question-1', 'prompt': 'Prompt only'}
          ],
        },
      );
      final attempt = FirestoreSerializers.quizAttemptFromMap(
        'attempt-1',
        const {
          'sessionId': 'quiz-1',
          'responses': [
            {
              'question': {'id': 'question-1'},
            }
          ],
        },
      );

      expect(session.questions.single.correctAnswer, '');
      expect(attempt.responses.single.quantitySold, 0);
      expect(session.isActive, isFalse);
    });

    test('export helpers serialize approved recipes and weekly results', () {
      final recipeJson = approvedRecipesExportJson([
        CocktailRecipe(
          id: 'recipe-1',
          name: 'Approved Sour',
          category: 'Classics',
          glassware: 'Coupe',
          garnish: 'Orange twist',
          method: 'Shake and fine strain',
          notes: '',
          ingredients: const [
            RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
          ],
          sourceLabel: 'manual',
          needsReview: false,
          reviewFlags: const [],
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      ]);
      final resultsJson = weeklyResultsExportJson([
        QuizAttempt(
          id: 'attempt-1',
          sessionId: 'quiz-1',
          bartenderName: 'Jamie',
          submittedAt: DateTime(2026, 5, 13),
          scorePercent: 90,
          responses: const [],
          overpourLines: const [],
          underpourLines: const [],
          coachingAreas: const ['Approved Sour'],
          encouragement: 'Nice work.',
          weekId: 'week-1',
        ),
      ]);

      expect(recipeJson, contains('Approved Sour'));
      expect(resultsJson, contains('attempt-1'));
    });
  });
}

RecipeImportDraft _approvedDraft({
  required String id,
  required String name,
  required String ingredient,
  String garnish = 'Orange twist',
  String glassware = 'Coupe',
  String method = 'Shake and fine strain',
}) {
  return RecipeImportDraft(
    id: id,
    sourceLabel: 'manual',
    pageLabel: 'manual',
    name: name,
    category: 'Classics',
    glassware: glassware,
    garnish: garnish,
    method: method,
    notes: '',
    ingredients: [
      RecipeIngredient(ingredientName: ingredient, measureMl: 40),
    ],
    reviewFlags: const [],
    status: RecipeDraftStatus.approved,
    wasManuallyReviewed: true,
  );
}

const _environment = AppEnvironment(
  firebaseApiKey: '',
  firebaseAppId: '',
  firebaseMessagingSenderId: '',
  firebaseProjectId: '',
  firebaseAuthDomain: '',
  firebaseStorageBucket: '',
  demoManagerEmail: 'manager@example.com',
  demoManagerPassword: 'password',
  defaultVenueId: 'venue-1',
  appMode: AppMode.demo,
);

class _FakeAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => AppUser(
        id: 'manager-1',
        email: 'manager@example.com',
        displayName: 'Manager',
        role: UserRole.manager,
        venueId: 'venue-1',
        venueName: 'Venue One',
        createdAt: DateTime(2026, 1, 1),
        active: true,
      );

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    return currentUser!;
  }

  @override
  Future<void> signOut() async {}
}
