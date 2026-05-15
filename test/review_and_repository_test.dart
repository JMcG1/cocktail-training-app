import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/recipe_review_validator.dart';
import 'package:stock_variance_coach/core/utils/variance_math.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

void main() {
  group('Recipe review validator', () {
    test('flags suspicious OCR names for manual correction', () {
      const draft = RecipeImportDraft(
        id: 'draft-1',
        sourceLabel: 'ocr.txt',
        pageLabel: 'Page 11',
        name: 'SRAMBLE PLANT POT',
        category: 'Signature Cocktails',
        glassware: 'Plant pot',
        garnish: 'Mint sprig',
        method: 'Build in plant pot.',
        notes: '',
        ingredients: [
          RecipeIngredient(ingredientName: 'Beefeater Pink', measureMl: 30),
        ],
        reviewFlags: [],
        status: RecipeDraftStatus.pending,
        wasManuallyReviewed: false,
      );

      final review = RecipeReviewValidator.inspectDraft(draft);

      expect(review.confidence, RecipeConfidence.possibleOcrIssue);
      expect(review.issues.any((issue) => issue.isPossibleOcrIssue), isTrue);
    });

    test('catches missing names and invalid ml values', () {
      const draft = RecipeImportDraft(
        id: 'draft-2',
        sourceLabel: 'ocr.txt',
        pageLabel: 'Page 20',
        name: '',
        category: '',
        glassware: '',
        garnish: '',
        method: '',
        notes: '',
        ingredients: [
          RecipeIngredient(ingredientName: 'Vodka', measureMl: -5),
          RecipeIngredient(ingredientName: 'Vodka', measureMl: 25),
        ],
        reviewFlags: [],
        status: RecipeDraftStatus.pending,
        wasManuallyReviewed: false,
      );

      final review = RecipeReviewValidator.inspectDraft(draft);

      expect(review.hasBlockingIssues, isTrue);
      expect(
        review.issues.any(
          (issue) => issue.message.contains('Add the cocktail name'),
        ),
        isTrue,
      );
      expect(
        review.issues.any(
          (issue) =>
              issue.message.contains('needs to be greater than 0ml'),
        ),
        isTrue,
      );
      expect(
        review.issues.any(
          (issue) => issue.message.contains('appears more than once'),
        ),
        isTrue,
      );
    });
  });

  group('Training repository approval flow', () {
    RecipeImportDraft buildDraft({
      required String id,
      required String name,
      required RecipeDraftStatus status,
      required String ingredient,
      required double measure,
    }) {
      return RecipeImportDraft(
        id: id,
        sourceLabel: 'ocr.txt',
        pageLabel: 'Page',
        name: name,
        category: 'Imported',
        glassware: 'Coupe',
        garnish: 'Orange twist',
        method: 'Shake and fine strain.',
        notes: '',
        ingredients: [
          RecipeIngredient(ingredientName: ingredient, measureMl: measure),
        ],
        reviewFlags: const [],
        status: status,
        wasManuallyReviewed: status == RecipeDraftStatus.approved,
      );
    }

    test('saves only approved drafts and leaves pending drafts in review', () {
      final repository = LocalTrainingRepository();
      final approved = buildDraft(
        id: 'approved-1',
        name: 'Approved Cooler',
        status: RecipeDraftStatus.approved,
        ingredient: 'Vodka',
        measure: 40,
      );
      final pending = buildDraft(
        id: 'pending-1',
        name: 'Pending Cooler',
        status: RecipeDraftStatus.pending,
        ingredient: 'Gin',
        measure: 35,
      );
      final deleted = buildDraft(
        id: 'deleted-1',
        name: 'Deleted Cooler',
        status: RecipeDraftStatus.deleted,
        ingredient: 'Rum',
        measure: 30,
      );

      repository.saveImportedDrafts([approved, pending, deleted]);

      expect(repository.recipes.map((recipe) => recipe.name), [
        'Approved Cooler',
      ]);
      expect(repository.latestImportResult, isNotNull);
      expect(repository.latestImportResult!.drafts.map((draft) => draft.name), [
        'Pending Cooler',
      ]);
    });

    test(
      'only approved recipes power practice quizzes and stock filtering',
      () {
        final repository = LocalTrainingRepository();
        final approved = buildDraft(
          id: 'approved-2',
          name: 'Approved Sour',
          status: RecipeDraftStatus.approved,
          ingredient: 'Vodka',
          measure: 40,
        );
        final pending = buildDraft(
          id: 'pending-2',
          name: 'Pending Sour',
          status: RecipeDraftStatus.pending,
          ingredient: 'Vodka',
          measure: 50,
        );

        repository.saveImportedDrafts([approved, pending]);

        final practiceQuiz = repository.generatePracticeQuizSession(
          bartenderName: 'Jamie',
        );
        expect(practiceQuiz.questions, isNotEmpty);
        expect(
          practiceQuiz.questions.every(
            (question) => question.cocktailName == 'Approved Sour',
          ),
          isTrue,
        );

        final session = repository.createWeeklySession(
          label: 'Monday focus',
          weekStart: DateTime(2026, 5, 11),
          concerns: const [StockConcernItem(ingredientName: 'Vodka')],
        );
        expect(session.targetCocktailIds, ['approved-2']);
      },
    );

    test(
      'relevant cocktails are filtered correctly by selected concern ingredient',
      () {
        final repository = LocalTrainingRepository();
        repository.saveImportedDrafts([
          buildDraft(
            id: 'approved-vodka',
            name: 'Vodka Serve',
            status: RecipeDraftStatus.approved,
            ingredient: 'Vodka',
            measure: 40,
          ),
          buildDraft(
            id: 'approved-gin',
            name: 'Gin Serve',
            status: RecipeDraftStatus.approved,
            ingredient: 'Gin',
            measure: 45,
          ),
        ]);
        final controller = AppController(
          authRepository: _FakeAuthRepository(),
          trainingRepository: repository,
          environment: _environment,
        );

        final relevant = controller.relevantRecipesForConcernNames(['Vodka']);

        expect(relevant.map((recipe) => recipe.name), ['Vodka Serve']);
        expect(controller.concernIngredientNames, ['Gin', 'Vodka']);
      },
    );

    test('targeted stock quiz uses only relevant approved cocktails', () {
      final repository = LocalTrainingRepository();
      repository.saveImportedDrafts([
        buildDraft(
          id: 'approved-vodka-quiz',
          name: 'Vodka Quiz',
          status: RecipeDraftStatus.approved,
          ingredient: 'Vodka',
          measure: 40,
        ),
        buildDraft(
          id: 'approved-rum-quiz',
          name: 'Rum Quiz',
          status: RecipeDraftStatus.approved,
          ingredient: 'Rum',
          measure: 50,
        ),
      ]);
      final session = repository.createWeeklySession(
        label: 'Monday focus',
        weekStart: DateTime(2026, 5, 11),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      repository.saveBartenderSales(
        weekId: session.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(
            cocktailId: 'approved-vodka-quiz',
            cocktailName: 'Vodka Quiz',
            quantitySold: 8,
          ),
        ],
      );

      final quiz = repository.generateStockQuizSession(
        weekId: session.id,
        bartenderName: 'Jamie',
      );

      expect(quiz.questions, isNotEmpty);
      expect(
        quiz.questions.every(
          (question) => question.cocktailName == 'Vodka Quiz',
        ),
        isTrue,
      );
      expect(
        quiz.questions.where(
          (question) => question.kind == QuestionKind.ingredientMeasure,
        ),
        isNotEmpty,
      );
    });
  });

  group('Variance math', () {
    const question = QuizQuestion(
      id: 'question-1',
      cocktailId: 'cocktail-1',
      cocktailName: 'Vodka Quiz',
      kind: QuestionKind.ingredientMeasure,
      prompt: 'How much vodka is in Vodka Quiz?',
      options: ['35ml', '40ml', '45ml', '50ml'],
      correctAnswer: '40ml',
      ingredientName: 'Vodka',
      correctMeasureMl: 40,
    );

    test('handles potential overpour variance', () {
      final attempt = VarianceMath.buildAttempt(
        attemptId: 'attempt-1',
        sessionId: 'session-1',
        weekId: 'week-1',
        bartenderName: 'Jamie',
        responses: const [
          QuestionResponse(
            question: question,
            selectedAnswer: '50ml',
            isCorrect: false,
            quantitySold: 32,
            deltaMl: 10,
          ),
        ],
        ingredientsByName: const {
          'vodka': Ingredient(
            id: 'ingredient-1',
            name: 'Vodka',
            bottleSizeMl: 700,
            bottleCost: 28,
          ),
        },
        batches: const [],
      );

      expect(attempt.overpourLines.single.totalMl, 320);
      expect(attempt.underpourLines, isEmpty);
      expect(
        attempt.overpourLines.single.approximateValue,
        closeTo(12.8, 0.001),
      );
    });

    test('handles underpour separately as a consistency opportunity', () {
      final attempt = VarianceMath.buildAttempt(
        attemptId: 'attempt-2',
        sessionId: 'session-1',
        weekId: 'week-1',
        bartenderName: 'Jamie',
        responses: const [
          QuestionResponse(
            question: question,
            selectedAnswer: '35ml',
            isCorrect: false,
            quantitySold: 10,
            deltaMl: -5,
          ),
        ],
        ingredientsByName: const {},
        batches: const [],
      );

      expect(attempt.overpourLines, isEmpty);
      expect(attempt.underpourLines.single.totalMl, 50);
      expect(
        attempt.underpourLines.single.direction,
        VarianceDirection.underpour,
      );
    });

    test('missing sales quantity results in zero projected variance', () {
      final attempt = VarianceMath.buildAttempt(
        attemptId: 'attempt-3',
        sessionId: 'session-1',
        weekId: 'week-1',
        bartenderName: 'Jamie',
        responses: const [
          QuestionResponse(
            question: question,
            selectedAnswer: '50ml',
            isCorrect: false,
            quantitySold: 0,
            deltaMl: 10,
          ),
        ],
        ingredientsByName: const {},
        batches: const [],
      );

      expect(attempt.overpourLines, isEmpty);
      expect(attempt.underpourLines, isEmpty);
    });
  });
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
  AppUser? get currentUser => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<VenueInvite>> listVenueInvites({required String venueId}) async {
    return const [];
  }

  @override
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    return null;
  }

  @override
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  }) async {}

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return const [];
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {}
}
