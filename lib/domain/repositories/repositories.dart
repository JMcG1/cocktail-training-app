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
  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();
}

abstract class TrainingRepository {
  List<Ingredient> get ingredients;
  List<CocktailRecipe> get recipes;
  List<WeeklyConcernSession> get weeklySessions;
  List<QuizSession> get quizSessions;
  List<QuizAttempt> get quizAttempts;
  RecipeImportResult? get latestImportResult;

  Future<void> initialize();
  void configureVenue(String venueId);
  Future<void> loadManagerData();
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  });
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  });
  void clearImportPreview();
  void saveImportedDrafts(List<RecipeImportDraft> drafts);
  void saveIngredient(Ingredient ingredient);
  void saveRecipe(CocktailRecipe recipe);
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
  });
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
  });
  QuizAttempt submitQuizAttempt({
    required String sessionId,
    required String bartenderName,
    required Map<String, String> answers,
  });
  QuizSession? findQuizSession(String sessionId);
  void deactivateQuizSession(String sessionId);
}
