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
    test('loads curated asset into review drafts and keeps Pornstar Martini flagged', () async {
      final controller = AppController(
        authRepository: _FakeAuthRepository(),
        trainingRepository: LocalTrainingRepository(),
        environment: _environment,
      );
      await controller.initialize();

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
        contains('Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.'),
      );
      expect(review.isIncomplete, isTrue);
      expect(
        review.issues.any((issue) => issue.message.contains('Garnish is blank')),
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
    });

    test('import only new leaves existing cocktails out of the review batch', () async {
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
      await controller.initialize();

      final plan = await controller.importCuratedSpecs(
        conflictMode: CuratedImportConflictMode.importOnlyNew,
      );

      expect(plan.existingRecipes, 1);
      expect(plan.newRecipes, 46);
      expect(plan.importResult.drafts, hasLength(46));
      expect(
        plan.importResult.drafts.any((draft) => draft.name == 'Espresso Martini'),
        isFalse,
      );
    });

    test('update existing reuses the live recipe id and avoids duplicates on save', () async {
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
      await controller.initialize();

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

      final storedEspresso = repository.recipes.where((recipe) => recipe.name == 'Espresso Martini').toList();
      expect(storedEspresso, hasLength(1));
      expect(storedEspresso.single.id, 'existing-espresso');
      expect(storedEspresso.single.method, 'Shake and double strain');
      expect(storedEspresso.single.ingredients.length, 4);
    });

    test('asset file stays readable from the Flutter bundle path', () async {
      final raw = await rootBundle.loadString(CuratedRecipeImporter.assetPath);
      expect(raw, contains('"name": "Pornstar Martini"'));
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
  Future<AppUser> signInManager({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {}
}
