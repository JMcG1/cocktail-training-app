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
      },
    );

    test(
      'verified sync seeds the live venue set and hides non-curated extras',
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

        final result = await controller.syncVerifiedRecipes(
          overwriteExisting: true,
        );

        expect(result.cocktailsAdded + result.cocktailsUpdated, 37);
        expect(result.batchesAdded + result.batchesUpdated, 10);
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
      'verified sync is idempotent and downstream practice uses only curated cocktails',
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
      },
    );

    test(
      'curated draft preview stays out of the live recipe library until sync',
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

        expect(plan.importResult.drafts, isNotEmpty);
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
