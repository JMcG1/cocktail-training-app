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
          (issue) => issue.message.contains('needs to be greater than 0ml'),
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

    test(
      'practice quiz includes ingredient, cocktail, and batch question types',
      () {
        final repository = LocalTrainingRepository();
        repository.saveImportedDrafts([
          RecipeImportDraft(
            id: 'batch-draft',
            sourceLabel: 'test',
            pageLabel: '1',
            name: 'House Batch',
            category: 'Batch',
            glassware: '',
            garnish: '',
            method: '',
            notes: '',
            status: RecipeDraftStatus.approved,
            ingredients: const [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 500),
            ],
            reviewFlags: const [],
            wasManuallyReviewed: true,
            entityType: RecipeEntityType.batch,
            totalBatchVolumeMl: 500,
          ),
          RecipeImportDraft(
            id: 'cocktail-1',
            sourceLabel: 'test',
            pageLabel: '1',
            name: 'Batch Serve',
            category: 'Signature',
            glassware: 'Highball',
            garnish: 'Lime wedge',
            method: 'Build',
            notes: '',
            ingredients: const [
              RecipeIngredient(
                ingredientName: 'House Batch',
                measureMl: 125,
                referenceType: IngredientReferenceType.batch,
                linkedBatchId: 'batch-draft',
              ),
              RecipeIngredient(ingredientName: 'Soda', measureMl: 50),
            ],
            reviewFlags: const [],
            status: RecipeDraftStatus.approved,
            wasManuallyReviewed: true,
          ),
        ]);

        final quiz = repository.generatePracticeQuizSession(
          bartenderName: 'Jamie',
        );
        final kinds = quiz.questions.map((question) => question.kind).toSet();

        expect(kinds, contains(QuestionKind.ingredientChoice));
        expect(kinds, contains(QuestionKind.cocktailByIngredient));
        expect(kinds, contains(QuestionKind.batchAmount));
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

    test(
      'updates same-name approved recipes in place instead of duplicating',
      () {
        final repository = LocalTrainingRepository();
        repository.saveRecipe(
          const CocktailRecipe(
            id: 'existing-espresso',
            name: 'Espresso Martini',
            category: 'Legacy',
            glassware: 'Nick and Nora',
            garnish: 'Coffee beans',
            method: 'Legacy build',
            notes: 'Older venue wording.',
            ingredients: [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 35),
            ],
            sourceLabel: 'Venue library',
            needsReview: false,
            reviewFlags: [],
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        );

        repository.saveImportedDrafts([
          buildDraft(
            id: 'fresh-import-id',
            name: 'Espresso Martini',
            status: RecipeDraftStatus.approved,
            ingredient: 'Vodka',
            measure: 40,
          ).copyWith(
            method: 'Shake and double strain.',
            ingredients: const [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
              RecipeIngredient(ingredientName: 'Coffee liqueur', measureMl: 20),
            ],
          ),
        ]);

        final stored = repository.recipes
            .where((recipe) => recipe.name == 'Espresso Martini')
            .toList();
        expect(stored, hasLength(1));
        expect(stored.single.id, 'existing-espresso');
        expect(stored.single.method, 'Legacy build');
        expect(stored.single.ingredients.length, 1);
      },
    );

    test(
      'publishing approved batch drafts carries ingredients and batch links downstream',
      () {
        final repository = LocalTrainingRepository();

        repository.saveImportedDrafts([
          const RecipeImportDraft(
            id: 'house-colada-batch',
            sourceLabel: 'ocr.txt',
            pageLabel: 'Page 41',
            name: 'House Colada Batch',
            category: 'Batch Recipes',
            glassware: '',
            garnish: '',
            method: '',
            notes: 'Prep before service.',
            ingredients: [
              RecipeIngredient(ingredientName: 'Rum', measureMl: 500),
              RecipeIngredient(ingredientName: 'Coconut', measureMl: 300),
              RecipeIngredient(ingredientName: 'Pineapple', measureMl: 200),
            ],
            reviewFlags: [],
            status: RecipeDraftStatus.approved,
            wasManuallyReviewed: true,
            entityType: RecipeEntityType.batch,
            totalBatchVolumeMl: 1000,
          ),
          const RecipeImportDraft(
            id: 'house-colada',
            sourceLabel: 'ocr.txt',
            pageLabel: 'Page 42',
            name: 'House Colada',
            category: 'Signatures',
            glassware: 'Hurricane',
            garnish: 'Pineapple wedge',
            method: 'Build over cubed ice.',
            notes: '',
            ingredients: [
              RecipeIngredient(
                ingredientName: 'House Colada Batch',
                measureMl: 125,
              ),
            ],
            reviewFlags: [],
            status: RecipeDraftStatus.approved,
            wasManuallyReviewed: true,
          ),
        ]);

        expect(repository.batches.map((batch) => batch.name), [
          'House Colada Batch',
        ]);
        expect(
          repository.ingredients.map((ingredient) => ingredient.name).toSet(),
          containsAll(<String>{'Rum', 'Coconut', 'Pineapple'}),
        );
        final cocktail = repository.recipes.singleWhere(
          (recipe) => recipe.name == 'House Colada',
        );
        expect(cocktail.ingredients.single.isBatchReference, isTrue);
        expect(cocktail.ingredients.single.linkedBatchId, 'house-colada-batch');
      },
    );
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
  appBuildLabel: 'test-build',
  appBuildTimestamp: '2026-05-22T00:00:00Z',
  appVersionLabel: 'test-suite',
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
  Future<void> deleteVenueInvite({
    required String venueId,
    required String inviteId,
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
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  }) async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {}
}
