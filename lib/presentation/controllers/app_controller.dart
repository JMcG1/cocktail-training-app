import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/curated_recipe_importer.dart';
import '../../core/utils/manager_trial_helpers.dart';
import '../../core/utils/recipe_review_validator.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AuthRepository authRepository,
    required TrainingRepository trainingRepository,
    required AppEnvironment environment,
  })  : _authRepository = authRepository,
        _trainingRepository = trainingRepository,
        _environment = environment,
        _recipeTextParser = RecipeTextParser(),
        _curatedRecipeImporter = const CuratedRecipeImporter();

  final AuthRepository _authRepository;
  final TrainingRepository _trainingRepository;
  final AppEnvironment _environment;
  final RecipeTextParser _recipeTextParser;
  final CuratedRecipeImporter _curatedRecipeImporter;

  bool _isBusy = false;
  String? _errorMessage;
  QuizAttempt? _latestAttempt;
  bool _usingFirebase = false;
  String? _successMessage;
  RecipeImportResult? _latestImportResult;
  CuratedImportPlan? _latestCuratedImportPlan;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  AppUser? get currentUser => _authRepository.currentUser;
  bool get isDemoAuthMode => !_environment.hasFirebaseConfig;
  String get demoManagerEmail => _environment.demoManagerEmail;
  String get demoManagerPassword => _environment.demoManagerPassword;
  List<Ingredient> get ingredients => _trainingRepository.ingredients;
  List<CocktailRecipe> get recipes => _trainingRepository.recipes;
  List<BatchRecipe> get batches => _trainingRepository.batches;
  List<WeeklyConcernSession> get weeklySessions => _trainingRepository.weeklySessions;
  List<QuizSession> get quizSessions => _trainingRepository.quizSessions;
  List<QuizAttempt> get quizAttempts => _trainingRepository.quizAttempts;
  RecipeImportResult? get latestImportResult => _latestImportResult;
  QuizAttempt? get latestAttempt => _latestAttempt;
  bool get usingFirebase => _usingFirebase;
  String? get successMessage => _successMessage;
  CuratedImportPlan? get latestCuratedImportPlan => _latestCuratedImportPlan;
  String get appBuildLabel => '1.0.0+1';
  String get runtimeModeLabel => usingFirebase ? 'Firebase mode' : 'Demo mode';
  bool get isManagerAuthenticated =>
      currentUser != null &&
      (currentUser!.role == UserRole.manager || currentUser!.role == UserRole.owner);
  bool get needsVenueOnboarding => isManagerAuthenticated && currentUser!.venueId.trim().isEmpty;

  Future<void> initialize({bool usingFirebase = false}) async {
    _usingFirebase = usingFirebase;
    await _authRepository.initialize();
    _trainingRepository.configureVenue(
      currentUser?.venueId ?? _environment.defaultVenueId,
    );
    await _trainingRepository.initialize();
    if (isManagerAuthenticated) {
      await _trainingRepository.loadManagerData();
    }
    _latestImportResult = _trainingRepository.latestImportResult;
    _latestCuratedImportPlan = null;
    notifyListeners();
  }

  Future<bool> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    return _wrapBusy(() async {
      _successMessage = null;
      final user = await _authRepository.createManagerAccount(
        email: email,
        password: password,
        displayName: displayName,
        venueName: venueName,
      );
      _trainingRepository.configureVenue(user.venueId);
      await _trainingRepository.initialize();
      await _trainingRepository.loadManagerData();
      _successMessage = 'Welcome to $venueName. Your venue is ready for setup.';
      return true;
    });
  }

  Future<bool> signInManager({
    required String email,
    required String password,
  }) async {
    return _wrapBusy(() async {
      _successMessage = null;
      final user = await _authRepository.signInManager(email: email, password: password);
      _trainingRepository.configureVenue(user.venueId);
      await _trainingRepository.initialize();
      await _trainingRepository.loadManagerData();
      _successMessage = 'Signed in. Ready to guide service with supportive coaching.';
      return true;
    });
  }

  Future<void> sendPasswordReset({required String email}) async {
    await _wrapBusy(() async {
      await _authRepository.sendPasswordReset(email: email);
      _successMessage =
          'If that address is linked to a manager account, a reset link is on its way.';
    });
  }

  Future<void> signOut() async {
    await _wrapBusy(() async {
      await _authRepository.signOut();
      _trainingRepository.configureVenue(_environment.defaultVenueId);
      await _trainingRepository.initialize();
      _latestAttempt = null;
      _successMessage = 'Signed out successfully.';
    });
  }

  RecipeImportDraft? parseRecipeFromText(String source) {
    return _recipeTextParser.parseSingleRecipe(
      source: source,
      fallbackId: 'recipe-${DateTime.now().microsecondsSinceEpoch}',
      sourceName: 'Manual entry',
    );
  }

  Future<RecipeImportResult> importPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final result = await _wrapBusy(
      () => _trainingRepository.extractRecipesFromPdf(bytes: bytes, fileName: fileName),
    );
    _latestImportResult = result;
    _latestCuratedImportPlan = null;
    notifyListeners();
    return result;
  }

  RecipeImportResult importFromOcrText({
    required String text,
    required String sourceName,
  }) {
    final result = _trainingRepository.extractRecipesFromText(
      text: text,
      sourceName: sourceName,
    );
    _latestImportResult = result;
    _latestCuratedImportPlan = null;
    notifyListeners();
    return result;
  }

  Future<CuratedImportPlan> importCuratedSpecs({
    required CuratedImportConflictMode conflictMode,
  }) async {
    final plan = await _wrapBusy(() async {
      final jsonText = await rootBundle.loadString(CuratedRecipeImporter.assetPath);
      final batchJsonText = await rootBundle.loadString(CuratedRecipeImporter.batchAssetPath);
      return _curatedRecipeImporter.buildPlan(
        cocktailJsonText: jsonText,
        batchJsonText: batchJsonText,
        existingRecipes: recipes,
        existingBatches: batches,
        conflictMode: conflictMode,
      );
    });
    _latestCuratedImportPlan = plan;
    _latestImportResult = plan.importResult;
    notifyListeners();
    return plan;
  }

  void clearImportPreview() {
    _trainingRepository.clearImportPreview();
    _latestImportResult = null;
    _latestCuratedImportPlan = null;
    notifyListeners();
  }

  RecipeImportDraft approveImportDraft(RecipeImportDraft draft) {
    final review = RecipeReviewValidator.inspectDraft(draft);
    if (!review.canApprove) {
      throw Exception(
        'This recipe still has blocking issues. Please fix them before approving it.',
      );
    }
    debugPrint(
      '[RecipeImport] Approving draft id=${draft.id} name="${draft.name}" confidence=${review.confidence.name}',
    );
    return draft.copyWith(
      status: RecipeDraftStatus.approved,
      wasManuallyReviewed: true,
    );
  }

  RecipeImportDraft keepImportDraftInReview(RecipeImportDraft draft) {
    debugPrint('[RecipeImport] Keeping draft in review id=${draft.id} name="${draft.name}"');
    return draft.copyWith(
      status: RecipeDraftStatus.pending,
      wasManuallyReviewed: true,
    );
  }

  RecipeImportDraft deleteImportDraft(RecipeImportDraft draft) {
    debugPrint('[RecipeImport] Deleting draft id=${draft.id} name="${draft.name}"');
    return draft.copyWith(
      status: RecipeDraftStatus.deleted,
      wasManuallyReviewed: true,
    );
  }

  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    final approvedCount =
        drafts.where((draft) => draft.status == RecipeDraftStatus.approved).length;
    final pendingCount =
        drafts.where((draft) => draft.status == RecipeDraftStatus.pending).length;
    final deletedCount =
        drafts.where((draft) => draft.status == RecipeDraftStatus.deleted).length;
    debugPrint(
      '[RecipeImport] Save requested approved=$approvedCount pending=$pendingCount deleted=$deletedCount',
    );
    await _wrapBusy(() async {
      await _trainingRepository.saveImportedDrafts(drafts);
      _latestImportResult = _trainingRepository.latestImportResult;
      if (_latestImportResult == null) {
        _latestCuratedImportPlan = null;
      }
    });
    debugPrint('[RecipeImport] Save finished approved=$approvedCount pending=$pendingCount');
    notifyListeners();
  }

  void saveIngredient({
    required String name,
    required double bottleSizeMl,
    required double bottleCost,
  }) {
    final existing = ingredients.cast<Ingredient?>().firstWhere(
          (item) => item!.name.toLowerCase() == name.toLowerCase(),
          orElse: () => null,
        );
    _trainingRepository.saveIngredient(
      Ingredient(
        id: existing?.id ?? 'ingredient-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        bottleSizeMl: bottleSizeMl,
        bottleCost: bottleCost,
      ),
    );
    notifyListeners();
  }

  void saveRecipe(CocktailRecipe recipe) {
    _trainingRepository.saveRecipe(recipe);
    notifyListeners();
  }

  void saveBatch(BatchRecipe batch) {
    _trainingRepository.saveBatch(batch);
    notifyListeners();
  }

  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final result = _trainingRepository.createWeeklySession(
      label: label,
      weekStart: weekStart,
      concerns: concerns,
    );
    notifyListeners();
    return result;
  }

  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  }) {
    _trainingRepository.saveBartenderSales(
      weekId: weekId,
      bartenderName: bartenderName,
      entries: entries,
    );
    notifyListeners();
  }

  QuizSession generateStockQuiz({
    required String weekId,
    required String bartenderName,
  }) {
    final session = _trainingRepository.generateStockQuizSession(
      weekId: weekId,
      bartenderName: bartenderName,
    );
    notifyListeners();
    return session;
  }

  QuizSession generatePracticeQuiz({
    required String bartenderName,
    List<String>? focusRecipeIds,
  }) {
    final session = _trainingRepository.generatePracticeQuizSession(
      bartenderName: bartenderName,
      focusRecipeIds: focusRecipeIds,
    );
    notifyListeners();
    return session;
  }

  QuizSession? findQuizSession(String sessionId) {
    return _trainingRepository.findQuizSession(sessionId);
  }

  void deactivateQuizSession(String sessionId) {
    _trainingRepository.deactivateQuizSession(sessionId);
    notifyListeners();
  }

  QuizAttempt submitQuizAttempt({
    required String sessionId,
    required String bartenderName,
    required Map<String, String> answers,
  }) {
    final attempt = _trainingRepository.submitQuizAttempt(
      sessionId: sessionId,
      bartenderName: bartenderName,
      answers: answers,
    );
    _latestAttempt = attempt;
    notifyListeners();
    return attempt;
  }

  WeeklyConcernSession? findWeeklySession(String id) {
    for (final session in weeklySessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  Map<String, CocktailRecipe> get recipesById =>
      UnmodifiableMapView({for (final recipe in recipes) recipe.id: recipe});

  List<String> get concernIngredientNames {
    final names = <String>{
      for (final recipe in recipes)
        ...recipe.ingredients.map((ingredient) => ingredient.ingredientName.trim()).where((name) => name.isNotEmpty),
      for (final batch in batches)
        ...batch.ingredients.map((ingredient) => ingredient.ingredientName.trim()).where((name) => name.isNotEmpty),
    }.toList()
      ..sort();
    return names;
  }

  List<CocktailRecipe> relevantRecipesForConcernNames(Iterable<String> concernNames) {
    final normalized = concernNames.map((name) => name.toLowerCase()).toSet();
    return recipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: normalized.map(BatchGraphResolver.normalizeKey).toSet(),
            batches: batches,
            ingredientsByName: {
              for (final ingredient in ingredients)
                BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
            },
          ),
        )
        .toList();
  }

  Map<String, List<CocktailRecipe>> relevantRecipesGroupedByConcern(
    WeeklyConcernSession session,
  ) {
    final grouped = <String, List<CocktailRecipe>>{};
    for (final concern in session.concerns) {
      grouped[concern.ingredientName] = recipes
          .where(
            (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
              cocktail: recipe,
              concernNames: {BatchGraphResolver.normalizeKey(concern.ingredientName)},
              batches: batches,
              ingredientsByName: {
                for (final ingredient in ingredients)
                  BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
              },
            ),
          )
          .toList();
    }
    return grouped;
  }

  List<CocktailRecipe> searchRecipes(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return recipes;
    }
    return recipes
        .where(
          (recipe) =>
              recipe.name.toLowerCase().contains(normalized) ||
              recipe.category.toLowerCase().contains(normalized) ||
              recipe.ingredients.any(
                (ingredient) => ingredient.ingredientName.toLowerCase().contains(normalized),
              ),
        )
        .toList();
  }

  List<CocktailRecipe> weakAreaRecipeSuggestions() {
    final counts = <String, int>{};
    for (final attempt in quizAttempts) {
      for (final response in attempt.responses.where((item) => !item.isCorrect)) {
        counts.update(
          response.question.cocktailId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final ids = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ids
        .map((entry) => recipesById[entry.key])
        .whereType<CocktailRecipe>()
        .take(6)
        .toList();
  }

  RecipeDraftCounts draftCounts(List<RecipeImportDraft> drafts) {
    return ManagerTrialHelpers.countDrafts(drafts);
  }

  List<RecipeImportDraft> filterDrafts({
    required List<RecipeImportDraft> drafts,
    String query = '',
    RecipeConfidence? confidence,
    String? category,
    bool includeDeleted = false,
  }) {
    return ManagerTrialHelpers.filterDrafts(
      drafts: drafts,
      query: query,
      confidence: confidence,
      category: category,
      includeDeleted: includeDeleted,
    );
  }

  SalesValidationResult validateBartenderSales({
    required WeeklyConcernSession session,
    required String bartenderName,
    required Map<String, String> rawQuantitiesByCocktailId,
  }) {
    return ManagerTrialHelpers.validateBartenderSales(
      session: session,
      bartenderName: bartenderName,
      rawQuantitiesByCocktailId: rawQuantitiesByCocktailId,
    );
  }

  StockWorkflowProgress stockWorkflowProgress(WeeklyConcernSession? session) {
    return ManagerTrialHelpers.buildStockWorkflowProgress(
      session: session,
      quizSessions: quizSessions,
      quizAttempts: quizAttempts,
    );
  }

  DashboardViewData buildDashboard() {
    final attempts = quizAttempts;
    final latestPerBartender = <String, QuizAttempt>{};
    final potentialVarianceByIngredient = <String, double>{};
    final potentialVarianceByBatch = <String, double>{};
    final potentialVarianceByBartender = <String, double>{};
    final misunderstoodCocktails = <String, int>{};
    final trainingFocusAreas = <String, int>{};
    final underpourOpportunities = <String, double>{};
    final quizCompletionStatus = <String, String>{};
    final weeklyConfidence = <String, int>{};
    final ingredientConfidenceByWeek = <String, Map<String, int>>{};
    final bartenderAverageScores = <String, int>{};
    final ingredientMisses = <String, int>{};
    final bartenderAttempts = <String, List<QuizAttempt>>{};

    for (final attempt in attempts) {
      latestPerBartender.putIfAbsent(attempt.bartenderName, () => attempt);
      bartenderAttempts.putIfAbsent(attempt.bartenderName, () => []).add(attempt);
      final bartenderTotal = attempt.overpourLines.fold<double>(
        0,
        (sum, line) => sum + line.approximateValue,
      ) +
          attempt.batchOverpourLines.fold<double>(
            0,
            (sum, line) => sum + line.approximateValue,
          );
      potentialVarianceByBartender.update(
        attempt.bartenderName,
        (value) => value + bartenderTotal,
        ifAbsent: () => bartenderTotal,
      );

      for (final line in attempt.overpourLines) {
        potentialVarianceByIngredient.update(
          line.ingredientName,
          (value) => value + line.approximateValue,
          ifAbsent: () => line.approximateValue,
        );
      }
      for (final line in attempt.batchOverpourLines) {
        potentialVarianceByBatch.update(
          line.ingredientName,
          (value) => value + line.totalMl,
          ifAbsent: () => line.totalMl,
        );
      }
      for (final line in attempt.underpourLines) {
        underpourOpportunities.update(
          line.ingredientName,
          (value) => value + line.totalMl,
          ifAbsent: () => line.totalMl,
        );
      }

      for (final response in attempt.responses.where((item) => !item.isCorrect)) {
        misunderstoodCocktails.update(
          response.question.cocktailName,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        trainingFocusAreas.update(
          response.question.kind.name,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if ((response.question.ingredientName ?? '').trim().isNotEmpty) {
          ingredientMisses.update(
            response.question.ingredientName!.trim(),
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }

      if (attempt.weekId != null) {
        final label = findWeeklySession(attempt.weekId!)?.label ?? attempt.weekId!;
        weeklyConfidence.update(
          label,
          (value) => ((value + attempt.scorePercent) / 2).round(),
          ifAbsent: () => attempt.scorePercent,
        );
        final ingredientWeekMap = ingredientConfidenceByWeek.putIfAbsent(label, () => {});
        final ingredientStats = <String, List<bool>>{};
        for (final response in attempt.responses.where(
          (item) =>
              item.question.kind == QuestionKind.ingredientMeasure &&
              (item.question.ingredientName ?? '').trim().isNotEmpty,
        )) {
          ingredientStats
              .putIfAbsent(response.question.ingredientName!.trim(), () => [])
              .add(response.isCorrect);
        }
        ingredientStats.forEach((ingredient, values) {
          final percent =
              ((values.where((item) => item).length / values.length) * 100).round();
          ingredientWeekMap.update(
            ingredient,
            (existing) => ((existing + percent) / 2).round(),
            ifAbsent: () => percent,
          );
        });
      }
    }

    bartenderAttempts.forEach((bartender, items) {
      final average =
          (items.map((attempt) => attempt.scorePercent).reduce((a, b) => a + b) / items.length)
              .round();
      bartenderAverageScores[bartender] = average;
    });

    for (final session in weeklySessions) {
      final completed = attempts
          .where((attempt) => attempt.weekId == session.id)
          .map((attempt) => attempt.bartenderName.toLowerCase())
          .toSet();
      final invited = session.bartenderSales.map((sales) => sales.bartenderName.toLowerCase()).toSet();
      quizCompletionStatus[session.label] = invited.isEmpty
          ? 'No bartender sales yet'
          : '${completed.length}/${invited.length} completed';
    }

    final quizCompletionRate = weeklySessions.isEmpty
        ? 0
        : ((weeklySessions
                        .where(
                          (session) => session.bartenderSales.isNotEmpty,
                        )
                        .length /
                    weeklySessions.length) *
                100)
            .round();
    final venueAverageScore = attempts.isEmpty
        ? 0
        : (attempts.map((attempt) => attempt.scorePercent).reduce((a, b) => a + b) /
                attempts.length)
            .round();
    final strongestImprovement = _strongestImprovement(bartenderAttempts);
    final activeQuizSessions = quizSessions.where((session) => session.isActive).length;
    final closedQuizSessions = quizSessions.where((session) => !session.isActive).length;
    final unresolvedStockSessions = weeklySessions.where((session) {
      final hasAttempt = attempts.any((attempt) => attempt.weekId == session.id);
      return !hasAttempt;
    }).length;

    return DashboardViewData(
      latestSessions: weeklySessions.take(2).toList(),
      latestPerBartender: latestPerBartender,
      potentialVarianceByIngredient: potentialVarianceByIngredient,
      potentialVarianceByBatch: potentialVarianceByBatch,
      potentialVarianceByBartender: potentialVarianceByBartender,
      misunderstoodCocktails: misunderstoodCocktails,
      trainingFocusAreas: trainingFocusAreas,
      weakAreaSuggestions: weakAreaRecipeSuggestions(),
      underpourOpportunities: underpourOpportunities,
      quizCompletionStatus: quizCompletionStatus,
      weeklyConfidence: weeklyConfidence,
      ingredientConfidenceByWeek: ingredientConfidenceByWeek,
      bartenderAverageScores: bartenderAverageScores,
      ingredientMisses: ingredientMisses,
      venueAverageScore: venueAverageScore,
      quizCompletionRate: quizCompletionRate,
      activeQuizSessions: activeQuizSessions,
      closedQuizSessions: closedQuizSessions,
      unresolvedStockSessions: unresolvedStockSessions,
      strongestImprovementLabel: strongestImprovement.$1,
      strongestImprovementDelta: strongestImprovement.$2,
    );
  }

  SetupChecklistData buildSetupChecklist() {
    final hasApprovedRecipes = recipes.isNotEmpty;
    final hasIngredientCosts = ingredients.any((ingredient) => ingredient.bottleCost > 0);
    final hasStockSession = weeklySessions.isNotEmpty;
    final hasSales = weeklySessions.any((session) => session.bartenderSales.isNotEmpty);
    final hasQuiz = quizSessions.any((session) => session.kind == QuizKind.stockVariance);
    final hasAttempt = quizAttempts.any((attempt) => attempt.weekId != null);
    final items = [
      SetupChecklistItem(
        title: 'Import and review cocktail specs',
        description: 'Approve the recipes you want to use for training and stock coaching.',
        isComplete: hasApprovedRecipes,
      ),
      SetupChecklistItem(
        title: 'Add ingredient costs',
        description: 'Store bottle costs so potential variance can include an approximate value.',
        isComplete: hasIngredientCosts,
      ),
      SetupChecklistItem(
        title: 'Create your first stock concern session',
        description: 'Choose the ingredients of concern after stock take.',
        isComplete: hasStockSession,
      ),
      SetupChecklistItem(
        title: 'Enter bartender sales',
        description: 'Capture only the relevant cocktails for each bartender.',
        isComplete: hasSales,
      ),
      SetupChecklistItem(
        title: 'Launch a targeted quiz',
        description: 'Share an active quiz link for the current session.',
        isComplete: hasQuiz,
      ),
      SetupChecklistItem(
        title: 'Collect first quiz attempt',
        description: 'Once a bartender submits a session, your insights will start filling in.',
        isComplete: hasAttempt,
      ),
    ];
    return SetupChecklistData(items: items);
  }

  Future<T> _wrapBusy<T>(Future<T> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}

(String?, int) _strongestImprovement(Map<String, List<QuizAttempt>> attemptsByBartender) {
  String? bestBartender;
  var bestDelta = 0;
  attemptsByBartender.forEach((bartender, attempts) {
    if (attempts.length < 2) {
      return;
    }
    final ordered = [...attempts]..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final delta = ordered.last.scorePercent - ordered[ordered.length - 2].scorePercent;
    if (delta > bestDelta) {
      bestDelta = delta;
      bestBartender = bartender;
    }
  });
  return (bestBartender, bestDelta);
}

class DashboardViewData {
  const DashboardViewData({
    required this.latestSessions,
    required this.latestPerBartender,
    required this.potentialVarianceByIngredient,
    required this.potentialVarianceByBatch,
    required this.potentialVarianceByBartender,
    required this.misunderstoodCocktails,
    required this.trainingFocusAreas,
    required this.weakAreaSuggestions,
    required this.underpourOpportunities,
    required this.quizCompletionStatus,
    required this.weeklyConfidence,
    required this.ingredientConfidenceByWeek,
    required this.bartenderAverageScores,
    required this.ingredientMisses,
    required this.venueAverageScore,
    required this.quizCompletionRate,
    required this.activeQuizSessions,
    required this.closedQuizSessions,
    required this.unresolvedStockSessions,
    required this.strongestImprovementLabel,
    required this.strongestImprovementDelta,
  });

  final List<WeeklyConcernSession> latestSessions;
  final Map<String, QuizAttempt> latestPerBartender;
  final Map<String, double> potentialVarianceByIngredient;
  final Map<String, double> potentialVarianceByBatch;
  final Map<String, double> potentialVarianceByBartender;
  final Map<String, int> misunderstoodCocktails;
  final Map<String, int> trainingFocusAreas;
  final List<CocktailRecipe> weakAreaSuggestions;
  final Map<String, double> underpourOpportunities;
  final Map<String, String> quizCompletionStatus;
  final Map<String, int> weeklyConfidence;
  final Map<String, Map<String, int>> ingredientConfidenceByWeek;
  final Map<String, int> bartenderAverageScores;
  final Map<String, int> ingredientMisses;
  final int venueAverageScore;
  final int quizCompletionRate;
  final int activeQuizSessions;
  final int closedQuizSessions;
  final int unresolvedStockSessions;
  final String? strongestImprovementLabel;
  final int strongestImprovementDelta;
}

class SetupChecklistData {
  const SetupChecklistData({required this.items});

  final List<SetupChecklistItem> items;

  int get completedCount => items.where((item) => item.isComplete).length;
  bool get isComplete => completedCount == items.length;
}

class SetupChecklistItem {
  const SetupChecklistItem({
    required this.title,
    required this.description,
    required this.isComplete,
  });

  final String title;
  final String description;
  final bool isComplete;
}
