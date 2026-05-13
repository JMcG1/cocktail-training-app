import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/batch_recipe_graph.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/core/utils/recipe_review_validator.dart';
import 'package:stock_variance_coach/core/utils/recipe_text_parser.dart';
import 'package:stock_variance_coach/core/utils/variance_math.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

void main() {
  group('Batch OCR parsing', () {
    test('detects batch drafts and total volume from OCR batch pages', () {
      const source = '''
===== PAGE 41 =====
BATCH NAME BATCH NAME
PALMHOUSE COLADA BATCH
INGREDIENTS & VOLUMES
RUM 500ml
COCONUT 300ml
PINEAPPLE 200ml
10 DRINKS 1000ML YIELD
NOTES
Stir until combined.
''';

      final result = RecipeTextParser().parseImportText(
        source: source,
        sourceName: 'ocr.txt',
      );

      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.isBatch, isTrue);
      expect(result.drafts.single.totalBatchVolumeMl, 1000);
      expect(result.drafts.single.ingredients.map((item) => item.ingredientName), [
        'Rum',
        'Coconut',
        'Pineapple',
      ]);
    });
  });

  group('Batch linking and validation', () {
    test('curated import flags unresolved batch links instead of inventing them', () {
      const importer = CuratedRecipeImporter();
      final plan = importer.buildPlan(
        cocktailJsonText: '''
[
  {
    "id": "watermelon-spritz",
    "name": "Watermelon Spritz",
    "category": "Spritz",
    "ingredients": [{"ingredient": "Watermelon Spritz Batch", "amount": "75ml"}],
    "method": "Build",
    "glass": "Spritz",
    "garnish": "Watermelon",
    "ice": "Cubed",
    "notes": ""
  }
]
''',
        batchJsonText: '''
[
  {
    "id": "cantaloupe-spritz-batch",
    "name": "Cantaloupe Spritz Batch",
    "category": "Batch Recipes",
    "totalVolume": "3750ml",
    "ingredients": [{"ingredient": "Midi Blanc", "amount": "1250ml"}],
    "aliases": [],
    "reviewFlags": []
  }
]
''',
        existingRecipes: const [],
        existingBatches: const [],
        conflictMode: CuratedImportConflictMode.importOnlyNew,
      );

      final cocktailDraft = plan.importResult.drafts.singleWhere((draft) => !draft.isBatch);
      final review = RecipeReviewValidator.inspectDraft(cocktailDraft);

      expect(
        cocktailDraft.reviewFlags.any((flag) => flag.contains('Unresolved batch link')),
        isTrue,
      );
      expect(review.canApprove, isFalse);
    });

    test('prevents circular batch dependencies', () {
      final batches = [
        const BatchRecipe(
          id: 'batch-a',
          name: 'Batch A',
          category: 'Batch Recipes',
          notes: '',
          ingredients: [
            RecipeIngredient(
              ingredientName: 'Batch B',
              measureMl: 100,
              referenceType: IngredientReferenceType.batch,
              linkedBatchId: 'batch-b',
            ),
          ],
          totalBatchVolumeMl: 100,
          sourceLabel: 'test',
          needsReview: false,
          reviewFlags: [],
          isApproved: true,
          wasManuallyReviewed: true,
        ),
        const BatchRecipe(
          id: 'batch-b',
          name: 'Batch B',
          category: 'Batch Recipes',
          notes: '',
          ingredients: [
            RecipeIngredient(
              ingredientName: 'Batch A',
              measureMl: 100,
              referenceType: IngredientReferenceType.batch,
              linkedBatchId: 'batch-a',
            ),
          ],
          totalBatchVolumeMl: 100,
          sourceLabel: 'test',
          needsReview: false,
          reviewFlags: [],
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      ];

      final issues = BatchGraphResolver.validateBatches(batches);

      expect(
        issues.any((issue) => issue.message.contains('Circular batch dependency')),
        isTrue,
      );
    });
  });

  group('Batch variance and cost calculations', () {
    test('decomposes batch variance recursively and calculates cost impact', () {
      const batch = BatchRecipe(
        id: 'colada-batch',
        name: 'Palmhouse Colada Batch',
        category: 'Batch Recipes',
        notes: '',
        ingredients: [
          RecipeIngredient(ingredientName: 'Rum', measureMl: 500),
          RecipeIngredient(ingredientName: 'Coconut', measureMl: 300),
          RecipeIngredient(ingredientName: 'Pineapple', measureMl: 200),
        ],
        totalBatchVolumeMl: 1000,
        sourceLabel: 'test',
        needsReview: false,
        reviewFlags: [],
        isApproved: true,
        wasManuallyReviewed: true,
      );

      final attempt = VarianceMath.buildAttempt(
        attemptId: 'attempt-1',
        sessionId: 'session-1',
        weekId: 'week-1',
        bartenderName: 'Jamie',
        responses: const [
          QuestionResponse(
            question: QuizQuestion(
              id: 'question-1',
              cocktailId: 'cocktail-1',
              cocktailName: 'Palmhouse Colada',
              kind: QuestionKind.ingredientMeasure,
              prompt: 'How much Palmhouse Colada Batch goes into Palmhouse Colada?',
              options: ['105ml', '125ml', '145ml'],
              correctAnswer: '125ml',
              ingredientName: 'Palmhouse Colada Batch',
              correctMeasureMl: 125,
              ingredientReferenceType: IngredientReferenceType.batch,
              linkedBatchId: 'colada-batch',
            ),
            selectedAnswer: '145ml',
            isCorrect: false,
            quantitySold: 1,
            deltaMl: 20,
          ),
        ],
        ingredientsByName: const {
          'rum': Ingredient(id: 'rum', name: 'Rum', bottleSizeMl: 1000, bottleCost: 40),
          'coconut': Ingredient(id: 'coconut', name: 'Coconut', bottleSizeMl: 1000, bottleCost: 10),
          'pineapple': Ingredient(id: 'pineapple', name: 'Pineapple', bottleSizeMl: 1000, bottleCost: 5),
        },
        batches: const [batch],
      );

      expect(attempt.batchOverpourLines.single.totalMl, 20);
      expect(
        attempt.overpourLines.firstWhere((line) => line.ingredientName == 'Rum').totalMl,
        closeTo(10, 0.001),
      );
      expect(
        attempt.overpourLines.firstWhere((line) => line.ingredientName == 'Coconut').totalMl,
        closeTo(6, 0.001),
      );
      expect(
        attempt.overpourLines.firstWhere((line) => line.ingredientName == 'Pineapple').totalMl,
        closeTo(4, 0.001),
      );
      expect(attempt.batchOverpourLines.single.approximateValue, closeTo(0.48, 0.01));
    });
  });

  group('Stock propagation and dashboard reporting', () {
    test('stock concerns propagate through approved batches into cocktail targeting and dashboard totals', () async {
      final repository = LocalTrainingRepository();
      final controller = AppController(
        authRepository: _FakeAuthRepository(),
        trainingRepository: repository,
        environment: _environment,
      );
      await controller.initialize();

      controller.saveIngredient(
        name: 'Vodka',
        bottleSizeMl: 1000,
        bottleCost: 20,
      );
      controller.saveBatch(
        const BatchRecipe(
          id: 'martini-batch',
          name: 'Martini Batch',
          category: 'Batch Recipes',
          notes: '',
          ingredients: [
            RecipeIngredient(ingredientName: 'Vodka', measureMl: 500),
            RecipeIngredient(ingredientName: 'Vermouth', measureMl: 500),
          ],
          totalBatchVolumeMl: 1000,
          sourceLabel: 'test',
          needsReview: false,
          reviewFlags: [],
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      );
      controller.saveRecipe(
        const CocktailRecipe(
          id: 'martini',
          name: 'Martini',
          category: 'Classics',
          glassware: 'Coupe',
          garnish: 'Olive',
          method: 'Stir',
          notes: '',
          ingredients: [
            RecipeIngredient(
              ingredientName: 'Martini Batch',
              measureMl: 125,
              referenceType: IngredientReferenceType.batch,
              linkedBatchId: 'martini-batch',
            ),
          ],
          sourceLabel: 'test',
          needsReview: false,
          reviewFlags: [],
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      );

      final session = controller.createWeeklySession(
        label: 'Week focus',
        weekStart: DateTime(2026, 5, 13),
        concerns: const [StockConcernItem(ingredientName: 'Vodka')],
      );
      expect(session.targetCocktailIds, contains('martini'));

      controller.saveBartenderSales(
        weekId: session.id,
        bartenderName: 'Jamie',
        entries: const [
          BartenderSalesEntry(cocktailId: 'martini', cocktailName: 'Martini', quantitySold: 2),
        ],
      );
      final quiz = controller.generateStockQuiz(
        weekId: session.id,
        bartenderName: 'Jamie',
      );
      final batchQuestion = quiz.questions.firstWhere(
        (question) => question.ingredientName == 'Martini Batch',
      );
      controller.submitQuizAttempt(
        sessionId: quiz.id,
        bartenderName: 'Jamie',
        answers: {
          batchQuestion.id: '145ml',
          for (final question in quiz.questions.where((item) => item.id != batchQuestion.id))
            question.id: question.correctAnswer,
        },
      );
      final dashboard = controller.buildDashboard();

      expect(dashboard.potentialVarianceByBatch['Martini Batch'], isNotNull);
      expect(dashboard.potentialVarianceByIngredient['Vodka'], isNotNull);
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
  AppUser? get currentUser => AppUser(
        id: 'manager-1',
        email: 'manager@example.com',
        displayName: 'Manager',
        role: UserRole.owner,
        venueId: 'venue-1',
        venueName: 'Venue One',
        createdAt: DateTime(2026, 1, 1),
        active: true,
      );

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
  Future<AppUser> signInManager({required String email, required String password}) async {
    return currentUser!;
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return [currentUser!];
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
