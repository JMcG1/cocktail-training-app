import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Verified recipe sync', () {
    test(
      'verified catalog builds from curated source data with image mappings',
      () {
        final importer = const CuratedRecipeImporter();
        final catalog = importer.buildVerifiedCatalog(
          cocktailJsonText: File(
            'assets/data/cocktails.json',
          ).readAsStringSync(),
          batchJsonText: File('assets/data/batches.json').readAsStringSync(),
        );

        expect(catalog.recipes, hasLength(37));
        expect(catalog.batches, hasLength(10));
        expect(catalog.missingImageCount, 0);
        expect(
          catalog.recipes.every(
            (recipe) => (recipe.imageAssetPath ?? '').trim().isNotEmpty,
          ),
          isTrue,
        );

        final pornstar = catalog.recipes.firstWhere(
          (recipe) => recipe.name == 'Pornstar Martini',
        );
        final aperol = catalog.recipes.firstWhere(
          (recipe) => recipe.name == 'Aperol Spritz',
        );
        final pimms = catalog.recipes.firstWhere(
          (recipe) => recipe.name == "Pimm's & Lemonade",
        );
        expect(aperol.priceGbp, 11.75);
        expect(pimms.priceGbp, isNull);
        expect(pornstar.needsReview, isTrue);
        expect(
          pornstar.reviewFlags,
          contains(
            'Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.',
          ),
        );

        final cantaloupeBatch = catalog.batches.firstWhere(
          (batch) => batch.name == 'Cantaloupe Spritz Batch',
        );
        expect(cantaloupeBatch.needsReview, isTrue);
        expect(
          catalog.recipes.every(
            (recipe) =>
                recipe.isApproved &&
                recipe.wasManuallyReviewed &&
                recipe.sourceLabel == CuratedRecipeImporter.sourceLabel,
          ),
          isTrue,
        );
        expect(
          catalog.batches.every(
            (batch) =>
                batch.isApproved &&
                batch.wasManuallyReviewed &&
                batch.sourceLabel == CuratedRecipeImporter.sourceLabel,
          ),
          isTrue,
        );
      },
    );

    test(
      'sync backfills curated prices without overwriting existing recipe specs',
      () async {
        final repository = LocalTrainingRepository();
        final importer = const CuratedRecipeImporter();
        final catalog = importer.buildVerifiedCatalog(
          cocktailJsonText: File(
            'assets/data/cocktails.json',
          ).readAsStringSync(),
          batchJsonText: File('assets/data/batches.json').readAsStringSync(),
        );
        repository.saveRecipe(
          const CocktailRecipe(
            id: 'existing-aperol',
            name: 'Aperol Spritz',
            category: 'Venue Library',
            glassware: 'Custom Glass',
            garnish: 'Fresh orange fan',
            method: 'Legacy build',
            notes: 'Keep venue-specific service note.',
            ingredients: [
              RecipeIngredient(ingredientName: 'Aperol', measureMl: 45),
            ],
            sourceLabel: 'Venue review',
            needsReview: false,
            reviewFlags: [],
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        );
        await repository.syncVerifiedRecipes(
          recipes: catalog.recipes,
          batches: catalog.batches,
          overwriteExisting: false,
        );
        final stored = repository.recipes.firstWhere(
          (recipe) => recipe.id == 'existing-aperol',
        );

        expect(stored.priceGbp, 11.75);
        expect(stored.notes, 'Keep venue-specific service note.');
        expect(stored.method, 'Legacy build');
        expect(stored.garnish, 'Fresh orange fan');
        expect(stored.ingredients.single.measureMl, 45);
      },
    );

    test(
      'app initialize loads the fixed curated cocktail list automatically',
      () async {
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment,
        );

        await controller.initialize();

        expect(controller.recipes, hasLength(37));
        expect(controller.batches, hasLength(10));
        expect(controller.didAutoPrepareCocktailList, isFalse);
      },
    );

    test(
      'existing owner edits to a fixed cocktail persist after initialize',
      () async {
        final repository = LocalTrainingRepository();
        final importer = const CuratedRecipeImporter();
        final catalog = importer.buildVerifiedCatalog(
          cocktailJsonText: File(
            'assets/data/cocktails.json',
          ).readAsStringSync(),
          batchJsonText: File('assets/data/batches.json').readAsStringSync(),
        );
        final editedRecipe = catalog.recipes
            .firstWhere((recipe) => recipe.id == 'aperol-spritz')
            .copyWith(
              notes:
                  'Manager note: keep the orange slice fresh before service.',
            );
        repository.saveRecipe(editedRecipe);
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: repository,
          environment: _environment,
        );
        await controller.initialize();
        expect(controller.didAutoPrepareCocktailList, isFalse);
        expect(controller.recipes, hasLength(37));
        expect(
          controller.recipes
              .firstWhere((recipe) => recipe.id == 'aperol-spritz')
              .notes,
          'Manager note: keep the orange slice fresh before service.',
        );
      },
    );

    test(
      'fixed cocktail list hides non-curated extras after initialize',
      () async {
        final repository = LocalTrainingRepository();
        repository.saveRecipe(
          const CocktailRecipe(
            id: 'legacy-special',
            name: 'Legacy Special',
            category: 'Old Menu',
            glassware: 'Coupe',
            garnish: 'Cherry',
            method: 'Shake',
            notes: 'Legacy recipe left over from review flow.',
            ingredients: [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 50),
            ],
            sourceLabel: 'Firestore review import',
            needsReview: false,
            reviewFlags: [],
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        );
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: repository,
          environment: _environment,
        );
        await controller.initialize();

        expect(controller.recipes, hasLength(37));
        expect(controller.batches, hasLength(10));
        expect(
          controller.recipes.any((recipe) => recipe.name == 'Legacy Special'),
          isFalse,
        );
        expect(
          controller.recipes.every(
            (recipe) => recipe.sourceLabel == CuratedRecipeImporter.sourceLabel,
          ),
          isTrue,
        );
      },
    );

    test(
      'refreshing the fixed cocktail list is idempotent and practice uses only curated cocktails',
      () async {
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment,
        );
        await controller.initialize();

        final first = await controller.syncVerifiedRecipes(
          overwriteExisting: true,
        );
        final second = await controller.syncVerifiedRecipes(
          overwriteExisting: false,
        );

        expect(first.cocktailsAdded + first.cocktailsUpdated, 37);
        expect(second.cocktailsSkipped, 37);
        expect(second.batchesSkipped, 10);
        expect(controller.recipes, hasLength(37));

        final quiz = controller.generatePracticeQuiz(bartenderName: 'Jamie');
        expect(quiz.questions, isNotEmpty);
        expect(
          quiz.questions.every(
            (question) => controller.recipes.any(
              (recipe) => recipe.id == question.cocktailId,
            ),
          ),
          isTrue,
        );
        expect(
          quiz.questions.every(
            (question) =>
                controller.recipesById[question.cocktailId]?.sourceLabel ==
                CuratedRecipeImporter.sourceLabel,
          ),
          isTrue,
        );
        expect(
          quiz.questions
              .where((question) => question.kind == QuestionKind.batchAmount)
              .every((question) => (question.linkedBatchId ?? '').isNotEmpty),
          isTrue,
        );
      },
    );

    test(
      'curated draft preview stays out of the live recipe library',
      () async {
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment,
        );
        await controller.initialize();

        final plan = await controller.importCuratedSpecs(
          conflictMode: CuratedImportConflictMode.importOnlyNew,
        );

        expect(plan.importResult.drafts, isEmpty);
        expect(controller.latestImportResult, isNotNull);
        expect(controller.recipes, hasLength(37));
        expect(controller.batches, hasLength(10));
        expect(
          controller.recipes.every(
            (recipe) => recipe.sourceLabel == CuratedRecipeImporter.sourceLabel,
          ),
          isTrue,
        );
      },
    );

    test(
      'quiz attempt saving keeps curated cocktails as the active training source',
      () async {
        final controller = AppController(
          authRepository: _FakeOwnerAuthRepository(),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment,
        );
        await controller.initialize();

        final session = controller.generatePracticeQuiz(bartenderName: 'Jamie');
        final answers = {
          for (final question in session.questions)
            question.id: question.correctAnswer,
        };

        final attempt = controller.submitQuizAttempt(
          sessionId: session.id,
          bartenderName: 'Jamie',
          answers: answers,
        );

        expect(controller.latestAttempt, isNotNull);
        expect(controller.latestAttempt!.id, attempt.id);
        expect(attempt.responses, isNotEmpty);
        expect(
          attempt.responses.every(
            (response) => controller.recipesById.containsKey(
              response.question.cocktailId,
            ),
          ),
          isTrue,
        );
      },
    );
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

class _FakeOwnerAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => AppUser(
    id: 'owner-1',
    email: 'owner@example.com',
    displayName: 'Owner',
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
