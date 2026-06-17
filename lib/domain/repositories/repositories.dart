import 'dart:typed_data';

import '../models/models.dart';

abstract class AuthRepository {
  AppUser? get currentUser;
  Future<void> initialize();

  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  });
  Future<AppUser> signInManager({
    required String email,
    required String password,
  });
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  });
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  });
  Future<List<VenueInvite>> listVenueInvites({required String venueId});
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  });
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  });
  Future<void> deleteVenueInvite({
    required String venueId,
    required String inviteId,
  });
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  });
  Future<List<AppUser>> listVenueUsers({required String venueId});
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  });
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  });
  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();
}

abstract class TrainingRepository {
  List<Ingredient> get ingredients;
  List<CocktailRecipe> get recipes;
  List<BatchRecipe> get batches;
  List<WeeklyConcernSession> get weeklySessions;
  List<QuizSession> get quizSessions;
  List<QuizAttempt> get quizAttempts;
  RecipeImportResult? get latestImportResult;

  Future<void> initialize();
  void configureVenue(String venueId);
  Future<void> loadManagerData();
  Future<void> loadBartenderData({required String userId});
  Future<void> loadAdminData();
  Future<bool> ensureBundledCatalogLoaded();
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  });
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  });
  void clearImportPreview();
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts);
  Future<VerifiedRecipeSyncResult> syncVerifiedRecipes({
    required List<CocktailRecipe> recipes,
    required List<BatchRecipe> batches,
    bool overwriteExisting = false,
  });
  Future<void> saveIngredient(Ingredient ingredient);
  void saveRecipe(CocktailRecipe recipe);
  void saveBatch(BatchRecipe batch);
  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  });
  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  });
  QuizSession generateStockQuizSession({
    required String weekId,
    required String bartenderName,
    QuizFocus focus = QuizFocus.specs,
  });
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
    QuizFocus focus = QuizFocus.specs,
  });
  QuizAttempt submitQuizAttempt({
    required String sessionId,
    String? userId,
    required String bartenderName,
    required Map<String, String> answers,
  });
  Future<QuizSession?> fetchQuizSession(String sessionId);
  QuizSession? findQuizSession(String sessionId);
  void deactivateQuizSession(String sessionId);
}
