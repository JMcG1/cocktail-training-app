import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/core/utils/recipe_review_validator.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Curated cocktail asset import', () {
    test(
      'loads curated asset into review drafts and keeps Pornstar Martini flagged',
      () async {
        final controller = AppController(
          authRepository: _FakeAuthRepository(),
          trainingRepository: LocalTrainingRepository(),
          environment: _environment,
        );

        final plan = await controller.importCuratedSpecs(
          conflictMode: CuratedImportConflictMode.importOnlyNew,
        );

        expect(plan.totalRecipes, 47);
        expect(plan.importResult.drafts, hasLength(47));
        expect(controller.latestImportResult?.drafts, hasLength(47));

        final pornstar = plan.importResult.drafts.firstWhere(
          (draft) => draft.name == 'Pornstar Martini',
        );
        final review = RecipeReviewValidator.inspectDraft(pornstar);

        expect(pornstar.garnish, isEmpty);
        expect(
          pornstar.reviewFlags,
          contains(
            'Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.',
          ),
        );
        expect(review.isIncomplete, isTrue);
        expect(
          review.issues.any(
            (issue) => issue.message.contains('Garnish is blank'),
          ),
          isTrue,
        );

        final botanistMule = plan.importResult.drafts.firstWhere(
          (draft) => draft.name == 'Botanist Mule',
        );
        final gingerBeer = botanistMule.ingredients.firstWhere(
          (item) => item.ingredientName == 'Schweppes Ginger Beer',
        );
        expect(gingerBeer.measureMl, 200);
        expect(gingerBeer.preparationNote, 'Source amount: 200ml bottle');
      },
    );

    test(
      'import only new leaves existing cocktails out of the review batch',
      () async {
        final repository = LocalTrainingRepository();
        repository.saveRecipe(
          const CocktailRecipe(
            id: 'existing-espresso',
            name: 'Espresso Martini',
            category: 'Classics',
            glassware: 'Coupe Glass',
            garnish: 'Coffee beans',
            method: 'Stir',
            notes: 'Legacy venue version.',
            ingredients: [
              RecipeIngredient(ingredientName: 'Vodka', measureMl: 40),
            ],
            sourceLabel: 'Venue library',
            needsReview: false,
            reviewFlags: [],
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        );
        final controller = AppController(
          authRepository: _FakeAuthRepository(),
          trainingRepository: repository,
          environment: _environment,
        );

        final plan = await controller.importCuratedSpecs(
          conflictMode: CuratedImportConflictMode.importOnlyNew,
        );

        expect(plan.existingRecipes, 1);
        expect(plan.newRecipes, 46);
        expect(plan.importResult.drafts, hasLength(46));
        expect(
          plan.importResult.drafts.any(
            (draft) => draft.name == 'Espresso Martini',
          ),
          isFalse,
        );
      },
    );

    test(
      'update existing reuses the live recipe id and avoids duplicates on save',
      () async {
        final repository = LocalTrainingRepository();
        repository.saveRecipe(
          const CocktailRecipe(
            id: 'existing-espresso',
            name: 'Espresso Martini',
            category: 'Legacy category',
            glassware: 'Nick and Nora',
            garnish: 'Coffee beans',
            method: 'Legacy method',
            notes: 'Old venue wording.',
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
        final controller = AppController(
          authRepository: _FakeAuthRepository(),
          trainingRepository: repository,
          environment: _environment,
        );

        final plan = await controller.importCuratedSpecs(
          conflictMode: CuratedImportConflictMode.updateExisting,
        );
        final espresso = plan.importResult.drafts.firstWhere(
          (draft) => draft.name == 'Espresso Martini',
        );

        expect(espresso.id, 'existing-espresso');

        await controller.saveImportedDrafts([
          espresso.copyWith(
            status: RecipeDraftStatus.approved,
            wasManuallyReviewed: true,
          ),
        ]);

        final storedEspresso = repository.recipes
            .where((recipe) => recipe.name == 'Espresso Martini')
            .toList();
        expect(storedEspresso, hasLength(1));
        expect(storedEspresso.single.id, 'existing-espresso');
        expect(storedEspresso.single.method, 'Legacy method');
        expect(storedEspresso.single.ingredients.single.measureMl, 35);
        expect(storedEspresso.single.priceGbp, 12.95);
      },
    );

    test('asset file stays readable from the Flutter bundle path', () async {
      final raw = await rootBundle.loadString(CuratedRecipeImporter.assetPath);
      expect(raw, contains('"name": "Pornstar Martini"'));
    });
  });
}

const _environment = AppEnvironment(
  allowOwnerBootstrap: false,
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
