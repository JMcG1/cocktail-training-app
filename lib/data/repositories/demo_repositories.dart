import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../core/utils/asset_text_loader.dart';
import '../../core/utils/approved_cocktail_prices.dart';
import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/curated_recipe_importer.dart';
import '../../core/utils/legacy_recipe_ids.dart';
import '../../core/utils/pdf_recipe_extractor.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

class LocalTrainingRepository implements TrainingRepository {
  LocalTrainingRepository()
    : _textParser = RecipeTextParser(),
      _pdfExtractor = PdfRecipeExtractor(RecipeTextParser());

  static Future<VerifiedRecipeCatalog>? _bundledCatalogFuture;

  final RecipeTextParser _textParser;
  final PdfRecipeExtractor _pdfExtractor;
  final List<Ingredient> _ingredients = [];
  final List<CocktailRecipe> _recipes = [];
  final List<BatchRecipe> _batches = [];
  final List<WeeklyConcernSession> _weeklySessions = [];
  final List<QuizSession> _quizSessions = [];
  final List<QuizAttempt> _quizAttempts = [];
  TrainingSyncStatus _syncStatus = const TrainingSyncStatus(
    lastQuizSyncMessage: 'Saved on this device',
  );
  RecipeImportResult? _latestImportResult;
  int _idCounter = 0;

  @override
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  @override
  List<CocktailRecipe> get recipes => List.unmodifiable(_visibleRecipes);

  @override
  List<BatchRecipe> get batches => List.unmodifiable(_visibleBatches);

  @override
  List<WeeklyConcernSession> get weeklySessions =>
      List.unmodifiable(_weeklySessions.reversed);

  @override
  List<QuizSession> get quizSessions =>
      List.unmodifiable(_quizSessions.reversed);

  @override
  List<QuizAttempt> get quizAttempts =>
      List.unmodifiable(_quizAttempts.reversed);

  @override
  TrainingSyncStatus get syncStatus => _syncStatus;

  @override
  RecipeImportResult? get latestImportResult => _latestImportResult;

  List<CocktailRecipe> get _visibleRecipes {
    return List.unmodifiable(_recipes);
  }

  List<BatchRecipe> get _visibleBatches {
    return List.unmodifiable(_batches);
  }

  @override
  Future<void> initialize() async {
    _weeklySessions.clear();
    _quizAttempts.clear();
    _latestImportResult = null;
    await _loadBundledCocktailList();
  }

  @override
  void configureVenue(String venueId) {}

  Future<void> _loadBundledCocktailList() async {
    final existingRecipesById = <String, CocktailRecipe>{};
    for (final recipe in _recipes) {
      for (final candidate in cocktailIdCandidates(recipe.id)) {
        existingRecipesById[candidate] = recipe;
      }
    }
    final existingBatchesById = {for (final batch in _batches) batch.id: batch};
    final existingIngredientsByName = {
      for (final ingredient in _ingredients)
        ingredient.name.trim().toLowerCase(): ingredient,
    };
    final catalog = await _loadBundledCatalog();
    _recipes.clear();
    _batches.clear();
    _ingredients.clear();

    final batchInputs = catalog.batches
        .map((batch) => existingBatchesById[batch.id] ?? batch)
        .toList();
    for (final batch in batchInputs) {
      saveBatch(batch);
      for (final ingredient in batch.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        _ensureIngredientExists(
          ingredient.ingredientName,
          existingIngredient:
              existingIngredientsByName[ingredient.ingredientName
                  .trim()
                  .toLowerCase()],
        );
      }
    }

    final recipeInputs = catalog.recipes.map((recipe) {
      final existing = existingRecipesById[recipe.id];
      if (existing == null) {
        return recipe;
      }
      return existing.copyWith(priceGbp: existing.priceGbp ?? recipe.priceGbp);
    }).toList();
    for (final recipe in recipeInputs) {
      saveRecipe(recipe);
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        _ensureIngredientExists(
          ingredient.ingredientName,
          existingIngredient:
              existingIngredientsByName[ingredient.ingredientName
                  .trim()
                  .toLowerCase()],
        );
      }
    }
    debugPrint(
      '[TrainingCatalog] Bundled catalog active cocktails=${_recipes.length} batches=${_batches.length} ingredients=${_ingredients.length}',
    );
  }

  @override
  Future<void> loadManagerData() async {}

  @override
  Future<void> loadBartenderData({required String userId}) async {}

  @override
  Future<void> loadAdminData() async {}

  @override
  Future<bool> ensureBundledCatalogLoaded() async {
    if (_recipes.isNotEmpty) {
      return false;
    }
    await _loadBundledCocktailList();
    return _recipes.isNotEmpty;
  }

  Future<VerifiedRecipeCatalog> _loadBundledCatalog() async {
    try {
      return await (_bundledCatalogFuture ??= _loadBundledCatalogFresh());
    } catch (_) {
      _bundledCatalogFuture = null;
      rethrow;
    }
  }

  Future<VerifiedRecipeCatalog> _loadBundledCatalogFresh() async {
    try {
      final cocktailJsonText = await _loadAssetText(
        CuratedRecipeImporter.cocktailAssetPath,
      );
      final batchJsonText = await _loadAssetText(
        CuratedRecipeImporter.batchAssetPath,
      );
      final catalog = const CuratedRecipeImporter().buildVerifiedCatalog(
        cocktailJsonText: cocktailJsonText,
        batchJsonText: batchJsonText,
      );
      debugPrint(
        '[TrainingCatalog] Bundled catalog parsed cocktails=${catalog.recipes.length} batches=${catalog.batches.length} first=${catalog.recipes.isEmpty ? '<none>' : '${catalog.recipes.first.id}/${catalog.recipes.first.name}'}',
      );
      return catalog;
    } catch (error, stackTrace) {
      debugPrint(
        '[TrainingCatalog] Bundled catalog parse failed error=$error stack=$stackTrace',
      );
      throw Exception(
        'Cocktail list could not be loaded. Please refresh or contact admin.',
      );
    }
  }

  Future<String> _loadAssetText(String assetKey) async {
    return loadBundledAssetText(assetKey, logName: 'TrainingCatalog');
  }

  @override
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _latestImportResult = _normalizeImportResult(
      _pdfExtractor.extract(bytes: bytes, fileName: fileName),
    );
    return _latestImportResult!;
  }

  @override
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  }) {
    _latestImportResult = _normalizeImportResult(
      _textParser.parseImportText(source: text, sourceName: sourceName),
    );
    return _latestImportResult!;
  }

  @override
  void clearImportPreview() {
    _latestImportResult = null;
  }

  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    final approvedBatches = drafts
        .where(
          (draft) =>
              draft.status == RecipeDraftStatus.approved && draft.isBatch,
        )
        .map((draft) {
          final batch = draft.toBatchRecipe();
          return batch.copyWith(
            id: _resolvedBatchId(batch),
            isApproved: true,
            wasManuallyReviewed: true,
          );
        })
        .toList();
    for (final batch in approvedBatches) {
      saveBatch(batch);
      for (final ingredient in batch.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        _ensureIngredientExists(ingredient.ingredientName);
      }
    }

    final approvedDrafts = drafts
        .where(
          (draft) =>
              draft.status == RecipeDraftStatus.approved && !draft.isBatch,
        )
        .map((draft) {
          final recipe = draft.toRecipe();
          final existing = _findExistingRecipe(recipe);
          if (existing != null) {
            return existing.copyWith(
              isApproved: true,
              wasManuallyReviewed: true,
              priceGbp:
                  draft.priceGbp ??
                  recipe.priceGbp ??
                  approvedCocktailPriceGbpForName(draft.name) ??
                  existing.priceGbp,
            );
          }
          return recipe.copyWith(
            id: _resolvedRecipeId(recipe),
            isApproved: true,
            wasManuallyReviewed: true,
          );
        })
        .toList();
    final batchesAfterSave = {
      for (final batch in _batches) batch.id: batch,
      for (final batch in approvedBatches) batch.id: batch,
    }.values.toList();
    final linkedApprovedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: approvedDrafts,
      batches: batchesAfterSave,
    );
    for (final recipe in linkedApprovedRecipes) {
      saveRecipe(recipe);
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        _ensureIngredientExists(ingredient.ingredientName);
      }
    }
    final remainingDrafts = drafts
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .toList();
    _latestImportResult = remainingDrafts.isEmpty
        ? null
        : _normalizeImportResult(
            RecipeImportResult(
              sourceName: _latestImportResult?.sourceName ?? 'Import review',
              drafts: remainingDrafts,
              warnings: _latestImportResult?.warnings ?? const [],
              requiresOcr: false,
              rawText: _latestImportResult?.rawText ?? '',
              pageCount: _latestImportResult?.pageCount ?? 0,
            ),
          );
  }

  @override
  Future<VerifiedRecipeSyncResult> syncVerifiedRecipes({
    required List<CocktailRecipe> recipes,
    required List<BatchRecipe> batches,
    bool overwriteExisting = false,
  }) async {
    var cocktailsAdded = 0;
    var cocktailsUpdated = 0;
    var cocktailsSkipped = 0;
    var batchesAdded = 0;
    var batchesUpdated = 0;
    var batchesSkipped = 0;
    var ingredientsAdded = 0;

    final curatedBatches = <BatchRecipe>[];
    for (final batch in batches) {
      final existing = _findExistingBatch(batch);
      if (existing != null && !overwriteExisting) {
        batchesSkipped += 1;
        continue;
      }
      final resolved = batch.copyWith(
        id: existing?.id ?? batch.id,
        sourceLabel: CuratedRecipeImporter.sourceLabel,
        isApproved: true,
        wasManuallyReviewed: true,
      );
      curatedBatches.add(resolved);
      if (existing == null) {
        batchesAdded += 1;
      } else {
        batchesUpdated += 1;
      }
    }

    final batchState = {for (final item in _batches) item.id: item};
    for (final batch in curatedBatches) {
      batchState[batch.id] = batch;
    }
    final finalBatchList = batchState.values.toList();

    for (final batch in curatedBatches) {
      final normalized = _normalizeBatchWithCatalog(batch, finalBatchList);
      saveBatch(normalized);
      for (final ingredient in normalized.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        if (_ensureIngredientExists(ingredient.ingredientName)) {
          ingredientsAdded += 1;
        }
      }
    }

    final curatedRecipes = <CocktailRecipe>[];
    for (final recipe in recipes) {
      final existing = _findExistingRecipe(recipe);
      if (existing != null && !overwriteExisting) {
        final backfilled = _backfillRecipePrice(
          existing: existing,
          incoming: recipe,
        );
        if (backfilled != null) {
          saveRecipe(backfilled);
          cocktailsUpdated += 1;
        } else {
          cocktailsSkipped += 1;
        }
        continue;
      }
      curatedRecipes.add(
        recipe.copyWith(
          id: existing?.id ?? recipe.id,
          sourceLabel: CuratedRecipeImporter.sourceLabel,
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      );
      if (existing == null) {
        cocktailsAdded += 1;
      } else {
        cocktailsUpdated += 1;
      }
    }

    final linkedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: curatedRecipes
          .map(
            (recipe) => recipe.copyWith(
              name: recipe.name.trim(),
              category: recipe.category.trim(),
              glassware: recipe.glassware.trim(),
              garnish: recipe.garnish.trim(),
              method: recipe.method.trim(),
              notes: recipe.notes.trim(),
              priceGbp: recipe.priceGbp,
              ingredients: recipe.ingredients
                  .where((item) => item.ingredientName.trim().isNotEmpty)
                  .map(
                    (item) => item.copyWith(
                      ingredientName: item.ingredientName.trim(),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      batches: _batches,
    );
    for (final recipe in linkedRecipes) {
      saveRecipe(recipe);
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        if (_ensureIngredientExists(ingredient.ingredientName)) {
          ingredientsAdded += 1;
        }
      }
    }

    return VerifiedRecipeSyncResult(
      cocktailsAdded: cocktailsAdded,
      cocktailsUpdated: cocktailsUpdated,
      cocktailsSkipped: cocktailsSkipped,
      batchesAdded: batchesAdded,
      batchesUpdated: batchesUpdated,
      batchesSkipped: batchesSkipped,
      ingredientsAdded: ingredientsAdded,
      flaggedCocktails: recipes.where((recipe) => recipe.needsReview).length,
      flaggedBatches: batches.where((batch) => batch.needsReview).length,
      missingImages: recipes.where((recipe) => recipe.missingImage).length,
    );
  }

  @override
  Future<void> saveIngredient(Ingredient ingredient) async {
    final index = _ingredients.indexWhere(
      (item) =>
          item.id == ingredient.id ||
          item.name.toLowerCase() == ingredient.name.toLowerCase(),
    );
    if (index == -1) {
      _ingredients.add(ingredient);
    } else {
      _ingredients[index] = ingredient;
    }
  }

  @override
  void saveRecipe(CocktailRecipe recipe) {
    final normalized = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: [
        recipe.copyWith(
          name: recipe.name.trim(),
          category: recipe.category.trim(),
          glassware: recipe.glassware.trim(),
          garnish: recipe.garnish.trim(),
          method: recipe.method.trim(),
          notes: recipe.notes.trim(),
          priceGbp:
              recipe.priceGbp ?? approvedCocktailPriceGbpForName(recipe.name),
          ingredients: recipe.ingredients
              .where((item) => item.ingredientName.trim().isNotEmpty)
              .map(
                (item) =>
                    item.copyWith(ingredientName: item.ingredientName.trim()),
              )
              .toList(),
        ),
      ],
      batches: _batches,
    ).single;
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index == -1) {
      _recipes.add(normalized);
    } else {
      _recipes[index] = normalized;
    }
  }

  @override
  void saveBatch(BatchRecipe batch) {
    final normalizedIngredients = batch.ingredients
        .where((item) => item.ingredientName.trim().isNotEmpty)
        .map(
          (item) => item.copyWith(ingredientName: item.ingredientName.trim()),
        )
        .toList();
    final linkedIngredients = normalizedIngredients
        .map(
          (item) => BatchGraphResolver.linkIngredientToBatch(
            ingredient: item,
            batchIndex: BatchGraphResolver.buildBatchIndex(
              _batches.where((existing) => existing.id != batch.id),
            ),
          ),
        )
        .toList();
    final normalized = batch.copyWith(
      name: batch.name.trim(),
      category: batch.category.trim(),
      notes: batch.notes.trim(),
      ingredients: linkedIngredients,
      isApproved: true,
    );
    final index = _batches.indexWhere((item) => item.id == batch.id);
    if (index == -1) {
      _batches.add(normalized);
    } else {
      _batches[index] = normalized;
    }
    final relinked = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: _recipes,
      batches: _batches,
    );
    _recipes
      ..clear()
      ..addAll(relinked);
  }

  @override
  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final existing = _findMatchingWeeklySession(
      label: label,
      weekStart: weekStart,
      concerns: concerns,
    );
    if (existing != null) {
      return existing;
    }
    final concernNames = concerns
        .map((item) => item.ingredientName.toLowerCase())
        .toSet();
    final targetIds = _approvedRecipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: concernNames,
            batches: _visibleBatches,
            ingredientsByName: _ingredientsByName,
          ),
        )
        .map((recipe) => recipe.id)
        .toList();

    final session = WeeklyConcernSession(
      id: _nextId('week'),
      label: label,
      weekStart: weekStart,
      concerns: concerns,
      targetCocktailIds: targetIds,
      bartenderSales: const [],
      quizSessionIds: const [],
    );
    _weeklySessions.add(session);
    return session;
  }

  @override
  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  }) {
    final index = _weeklySessions.indexWhere((session) => session.id == weekId);
    if (index == -1) {
      return;
    }

    final current = _weeklySessions[index];
    final sales = [...current.bartenderSales];
    final salesIndex = sales.indexWhere(
      (record) =>
          record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
    );
    final updated = BartenderWeeklySales(
      bartenderName: bartenderName,
      entries: entries.where((entry) => entry.quantitySold > 0).toList(),
    );
    if (salesIndex == -1) {
      sales.add(updated);
    } else {
      sales[salesIndex] = updated;
    }
    _weeklySessions[index] = current.copyWith(bartenderSales: sales);
  }

  @override
  QuizSession generateStockQuizSession({
    required String weekId,
    required String bartenderName,
    QuizFocus focus = QuizFocus.specs,
  }) {
    final existing = _quizSessions.cast<QuizSession?>().firstWhere(
      (session) =>
          session != null &&
          session.weekId == weekId &&
          session.bartenderName.toLowerCase() == bartenderName.toLowerCase() &&
          session.isActive,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final weeklySession = _weeklySessions.firstWhere(
      (session) => session.id == weekId,
    );
    final targetRecipes = _approvedRecipes
        .where((recipe) => weeklySession.targetCocktailIds.contains(recipe.id))
        .toList();
    final concernNames = weeklySession.concerns
        .map((item) => BatchGraphResolver.normalizeKey(item.ingredientName))
        .toSet();
    final prioritizedQuestions = _buildQuestionsForFocus(
      recipes: targetRecipes,
      pool: targetRecipes,
      allowedIngredientNames: concernNames,
      focus: focus,
      seed: bartenderName,
    );
    final adaptiveQuestions = _adaptiveQuestionOrder(
      prioritizedQuestions,
      bartenderName: bartenderName,
      seed: '$bartenderName-stock',
    );

    final quiz = QuizSession(
      id: _nextId('quiz'),
      title: '${weeklySession.label} surprise quiz',
      bartenderName: bartenderName,
      kind: QuizKind.stockVariance,
      focus: focus,
      isActive: true,
      createdAt: DateTime.now(),
      questions: adaptiveQuestions
          .take(min(10, prioritizedQuestions.length))
          .toList(),
      weekId: weeklySession.id,
    );
    _quizSessions.add(quiz);
    _sortQuizSessions();
    final sessionIndex = _weeklySessions.indexWhere(
      (session) => session.id == weekId,
    );
    _weeklySessions[sessionIndex] = weeklySession.copyWith(
      quizSessionIds: [...weeklySession.quizSessionIds, quiz.id],
    );
    return quiz;
  }

  @override
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
    QuizFocus focus = QuizFocus.specs,
  }) {
    final allowedIds = focusRecipeIds?.toSet();
    final recipePool = allowedIds == null
        ? _approvedRecipes
        : _approvedRecipes
              .where((recipe) => allowedIds.contains(recipe.id))
              .toList();
    final questions = _buildQuestionsForFocus(
      recipes: recipePool,
      pool: _approvedRecipes,
      focus: focus,
      seed: bartenderName,
    );
    final adaptiveQuestions = _adaptiveQuestionOrder(
      questions,
      bartenderName: bartenderName,
      seed: '$bartenderName-practice',
    );

    final quiz = QuizSession(
      id: _nextId('quiz'),
      title: switch (focus) {
        QuizFocus.specs => 'Specs quiz',
        QuizFocus.garnishGlassware => 'Garnish and glass quiz',
      },
      bartenderName: bartenderName,
      kind: QuizKind.practice,
      focus: focus,
      isActive: true,
      createdAt: DateTime.now(),
      questions: adaptiveQuestions.take(min(10, adaptiveQuestions.length)).toList(),
    );
    _quizSessions.add(quiz);
    _sortQuizSessions();
    return quiz;
  }

  void importWeeklySessionSnapshot(WeeklyConcernSession session) {
    final existingIndex = _weeklySessions.indexWhere((item) => item.id == session.id);
    if (existingIndex == -1) {
      _weeklySessions.add(session);
    } else {
      _weeklySessions[existingIndex] = session;
    }
  }

  void importQuizAttemptSnapshot(QuizAttempt attempt) {
    final existingIndex = _quizAttempts.indexWhere((item) => item.id == attempt.id);
    if (existingIndex == -1) {
      _quizAttempts.add(attempt);
      _sortQuizAttempts();
    } else {
      _quizAttempts[existingIndex] = attempt;
      _sortQuizAttempts();
    }
  }

  List<CocktailRecipe> get _approvedRecipes {
    final approved = _recipes.where((recipe) => recipe.isApproved).toList();
    final curated = approved
        .where(
          (recipe) => recipe.sourceLabel == CuratedRecipeImporter.sourceLabel,
        )
        .toList();
    return curated.isNotEmpty ? curated : approved;
  }

  Map<String, Ingredient> get _ingredientsByName => {
    for (final ingredient in _ingredients)
      BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
  };

  @override
  Future<QuizAttempt> submitQuizAttempt({
    required String sessionId,
    String? userId,
    required String bartenderName,
    required Map<String, String> answers,
    Map<String, QuizAnswerConfidence> confidenceByQuestionId = const {},
    DateTime? startedAt,
  }) async {
    developer.log(
      'Quiz submitted session=$sessionId bartender=$bartenderName',
      name: 'QuizFlow',
      level: 800,
    );
    _syncStatus = _syncStatus.copyWith(
      quizWriteConfirmed: true,
      lastQuizSyncMessage: 'Saving quiz locally',
    );
    final existingAttempt = _quizAttempts.cast<QuizAttempt?>().firstWhere(
      (attempt) =>
          attempt != null &&
          attempt.sessionId == sessionId &&
          attempt.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
      orElse: () => null,
    );
    if (existingAttempt != null) {
      developer.log(
        'Quiz duplicate submission reused session=$sessionId bartender=$bartenderName attempt=${existingAttempt.id}',
        name: 'QuizFlow',
        level: 900,
      );
      return existingAttempt;
    }
    final sessionIndex = _quizSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex == -1) {
      throw Exception('This quiz session could not be found.');
    }
    final session = _quizSessions[sessionIndex];
    if (!session.isActive) {
      throw Exception(
        'This quiz session is no longer active. Ask your manager for a fresh link.',
      );
    }
    final missingAnswers = session.questions.where(
      (question) => (answers[question.id] ?? '').trim().isEmpty,
    );
    if (missingAnswers.isNotEmpty) {
      throw Exception('Please answer every question before submitting.');
    }
    final weeklySession = session.weekId == null
        ? null
        : _weeklySessions.firstWhere((item) => item.id == session.weekId);
    final sales =
        weeklySession?.bartenderSales.firstWhere(
          (record) =>
              record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => BartenderWeeklySales(
            bartenderName: bartenderName,
            entries: const [],
          ),
        ) ??
        BartenderWeeklySales(bartenderName: bartenderName, entries: const []);
    final quantityByCocktail = {
      for (final entry in sales.entries) entry.cocktailId: entry.quantitySold,
    };
    final usesFallbackSalesVolume = quantityByCocktail.isEmpty;
    final ingredientsByName = {
      for (final ingredient in _ingredients)
        BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
    };

    final responses = session.questions.map((question) {
      final selectedAnswer = answers[question.id] ?? '';
      final isCorrect = selectedAnswer == question.correctAnswer;
      final quantitySold = usesFallbackSalesVolume
          ? 30
          : (quantityByCocktail[question.cocktailId] ?? 0);
      double? deltaMl;
      if ((question.kind == QuestionKind.ingredientMeasure ||
              question.kind == QuestionKind.batchAmount) &&
          question.correctMeasureMl != null) {
        final selectedMl = _parseMeasure(selectedAnswer);
        if (selectedMl != null) {
          deltaMl = selectedMl - question.correctMeasureMl!;
        }
      }

      return QuestionResponse(
        question: question,
        selectedAnswer: selectedAnswer,
        isCorrect: isCorrect,
        quantitySold: quantitySold,
        confidence:
            confidenceByQuestionId[question.id] ?? QuizAnswerConfidence.unsure,
        deltaMl: deltaMl,
      );
    }).toList();

    final previousBestScorePercent = _quizAttempts
        .where(
          (attempt) =>
              (userId != null && attempt.userId == userId) ||
              attempt.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
        )
        .map((attempt) => attempt.scorePercent)
        .fold<int?>(null, (best, score) => best == null || score > best ? score : best);

    final attempt = VarianceMath.buildAttempt(
      attemptId: _attemptDocumentId(
        sessionId: session.id,
        userId: userId,
        bartenderName: bartenderName,
      ),
      sessionId: session.id,
      weekId: session.weekId,
      userId: userId,
      bartenderName: bartenderName,
      startedAt: startedAt ?? DateTime.now(),
      responses: responses,
      ingredientsByName: ingredientsByName,
      batches: _visibleBatches,
      previousBestScorePercent: previousBestScorePercent,
    );

    _quizAttempts.add(attempt);
    _quizSessions[sessionIndex] = session.copyWith(isActive: false);
    _sortQuizAttempts();
    _sortQuizSessions();
    developer.log(
      'Quiz marked and saved locally session=$sessionId attempt=${attempt.id} score=${attempt.scorePercent}',
      name: 'QuizFlow',
      level: 800,
    );
    _syncStatus = _syncStatus.copyWith(
      quizWriteConfirmed: true,
      lastQuizSyncMessage: 'Quiz saved locally',
    );
    return attempt;
  }

  @override
  Future<QuizSession?> fetchQuizSession(String sessionId) async {
    return findQuizSession(sessionId);
  }

  @override
  QuizSession? findQuizSession(String sessionId) {
    for (final session in _quizSessions) {
      if (session.id == sessionId && session.isActive) {
        return session;
      }
    }
    return null;
  }

  @override
  void deactivateQuizSession(String sessionId) {
    final index = _quizSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (index == -1) {
      return;
    }
    _quizSessions[index] = _quizSessions[index].copyWith(isActive: false);
    _sortQuizSessions();
  }

  bool _ensureIngredientExists(String name, {Ingredient? existingIngredient}) {
    final alreadyExists = _ingredients.any(
      (ingredient) => ingredient.name.toLowerCase() == name.toLowerCase(),
    );
    if (!alreadyExists) {
      _ingredients.add(
        existingIngredient ??
            Ingredient(
              id: _nextId('ingredient'),
              name: name,
              bottleSizeMl: 700,
              bottleCost: 0,
              isGarnish: false,
            ),
      );
      return true;
    }
    return false;
  }

  CocktailRecipe? _backfillRecipePrice({
    required CocktailRecipe existing,
    required CocktailRecipe incoming,
  }) {
    final incomingPrice =
        incoming.priceGbp ??
        approvedCocktailPriceGbpForName(incoming.name) ??
        approvedCocktailPriceGbpForName(existing.name);
    if (incomingPrice == null || existing.priceGbp == incomingPrice) {
      return null;
    }
    return existing.copyWith(priceGbp: incomingPrice);
  }

  CocktailRecipe? _findExistingRecipe(CocktailRecipe recipe) {
    final normalizedName = BatchGraphResolver.normalizeKey(recipe.name);
    final approvedNameKey = approvedCocktailNameMatchKey(recipe.name);
    final candidateIds = cocktailIdCandidates(recipe.id).toSet();
    return _recipes.cast<CocktailRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (candidateIds.contains(normalizeCocktailId(item.id)) ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName ||
              approvedCocktailNamesMatch(item.name, recipe.name) ||
              approvedCocktailNameMatchKey(item.name) == approvedNameKey),
      orElse: () => null,
    );
  }

  BatchRecipe? _findExistingBatch(BatchRecipe batch) {
    final normalizedName = BatchGraphResolver.normalizeKey(batch.name);
    return _batches.cast<BatchRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (item.id == batch.id ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName),
      orElse: () => null,
    );
  }

  BatchRecipe _normalizeBatchWithCatalog(
    BatchRecipe batch,
    List<BatchRecipe> batches,
  ) {
    final normalizedIngredients = batch.ingredients
        .where((item) => item.ingredientName.trim().isNotEmpty)
        .map(
          (item) => item.copyWith(ingredientName: item.ingredientName.trim()),
        )
        .toList();
    final linkedIngredients = normalizedIngredients
        .map(
          (item) => BatchGraphResolver.linkIngredientToBatch(
            ingredient: item,
            batchIndex: BatchGraphResolver.buildBatchIndex(
              batches.where((existing) => existing.id != batch.id),
            ),
          ),
        )
        .toList();
    return batch.copyWith(
      name: batch.name.trim(),
      category: batch.category.trim(),
      notes: batch.notes.trim(),
      ingredients: linkedIngredients,
      isApproved: true,
    );
  }

  String _resolvedRecipeId(CocktailRecipe recipe) {
    final normalizedName = BatchGraphResolver.normalizeKey(recipe.name);
    final existing = _recipes.cast<CocktailRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (normalizeCocktailId(item.id) == normalizeCocktailId(recipe.id) ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName ||
              approvedCocktailNamesMatch(item.name, recipe.name)),
      orElse: () => null,
    );
    return normalizeCocktailId(existing?.id ?? recipe.id);
  }

  String _resolvedBatchId(BatchRecipe batch) {
    final normalizedName = BatchGraphResolver.normalizeKey(batch.name);
    final existing = _batches.cast<BatchRecipe?>().firstWhere(
      (item) =>
          item != null &&
          BatchGraphResolver.normalizeKey(item.name) == normalizedName,
      orElse: () => null,
    );
    return existing?.id ?? batch.id;
  }

  String _attemptDocumentId({
    required String sessionId,
    required String? userId,
    required String bartenderName,
  }) {
    final actorKey = userId?.trim().isNotEmpty == true
        ? userId!.trim()
        : bartenderName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '$sessionId-$actorKey';
  }

  void _sortQuizSessions() {
    _quizSessions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _sortQuizAttempts() {
    _quizAttempts.sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
  }

  List<QuizQuestion> _buildQuestionsForFocus({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
    Set<String>? allowedIngredientNames,
    required QuizFocus focus,
    required String seed,
  }) {
    return switch (focus) {
      QuizFocus.specs => [
        ..._shuffleQuestions(
          _buildMeasureQuestions(
            recipes: recipes,
            pool: pool,
            allowedIngredientNames: allowedIngredientNames,
          ),
          seed,
        ),
        ..._shuffleQuestions(
          _buildBatchAmountQuestions(
            recipes: recipes,
            pool: pool,
            allowedIngredientNames: allowedIngredientNames,
          ),
          '$seed-batch',
        ),
        ..._shuffleQuestions(
          _buildIngredientChoiceQuestions(recipes: recipes, pool: pool),
          '$seed-ingredient-choice',
        ),
        ..._shuffleQuestions(
          _buildMissingIngredientQuestions(recipes: recipes, pool: pool),
          '$seed-missing-ingredient',
        ),
        ..._shuffleQuestions(
          _buildCocktailIdentificationQuestions(recipes: recipes, pool: pool),
          '$seed-cocktail-identification',
        ),
        ..._shuffleQuestions(
          _buildMethodQuestions(recipes: recipes, pool: pool),
          '$seed-method',
        ),
        ..._shuffleQuestions(
          _buildMethodOrderQuestions(recipes: recipes),
          '$seed-method-order',
        ),
      ],
      QuizFocus.garnishGlassware => [
        ..._shuffleQuestions(
          _buildGarnishGlassQuestions(recipes: recipes, pool: pool),
          '$seed-garnish-glass',
        ),
      ],
    };
  }

  List<QuizQuestion> _shuffleQuestions(
    List<QuizQuestion> questions,
    String seed,
  ) {
    final random = Random(seed.hashCode);
    return [...questions]..shuffle(random);
  }

  List<QuizQuestion> _adaptiveQuestionOrder(
    List<QuizQuestion> questions, {
    required String bartenderName,
    required String seed,
  }) {
    final normalizedBartender = bartenderName.trim().toLowerCase();
    final cocktailMisses = <String, int>{};
    final cocktailCorrects = <String, int>{};
    final highConfidenceMisses = <String, int>{};
    final questionTypeMisses = <String, int>{};
    final exposureByCocktail = <String, int>{};

    for (final session in _weeklySessions) {
      for (final sales in session.bartenderSales.where(
        (item) => item.bartenderName.trim().toLowerCase() == normalizedBartender,
      )) {
        for (final entry in sales.entries) {
          exposureByCocktail.update(
            entry.cocktailId,
            (value) => value + entry.quantitySold,
            ifAbsent: () => entry.quantitySold,
          );
        }
      }
    }

    for (final attempt in _quizAttempts.where(
      (item) => item.bartenderName.trim().toLowerCase() == normalizedBartender,
    )) {
      for (final response in attempt.responses) {
        final cocktailId = response.question.cocktailId;
        final kindKey = '$cocktailId|${response.question.kind.name}';
        if (response.isCorrect) {
          cocktailCorrects.update(
            cocktailId,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        } else {
          cocktailMisses.update(
            cocktailId,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          questionTypeMisses.update(
            kindKey,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          if (response.isHighConfidenceMiss) {
            highConfidenceMisses.update(
              cocktailId,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
          }
        }
      }
    }

    final ordered = [...questions];
    ordered.sort((a, b) {
      final scoreA = _adaptiveQuestionScore(
        a,
        cocktailMisses: cocktailMisses,
        cocktailCorrects: cocktailCorrects,
        highConfidenceMisses: highConfidenceMisses,
        questionTypeMisses: questionTypeMisses,
        exposureByCocktail: exposureByCocktail,
      );
      final scoreB = _adaptiveQuestionScore(
        b,
        cocktailMisses: cocktailMisses,
        cocktailCorrects: cocktailCorrects,
        highConfidenceMisses: highConfidenceMisses,
        questionTypeMisses: questionTypeMisses,
        exposureByCocktail: exposureByCocktail,
      );
      final byScore = scoreB.compareTo(scoreA);
      if (byScore != 0) {
        return byScore;
      }
      final tieA = Object.hash(seed, a.id, a.cocktailId);
      final tieB = Object.hash(seed, b.id, b.cocktailId);
      return tieA.compareTo(tieB);
    });
    return ordered;
  }

  int _adaptiveQuestionScore(
    QuizQuestion question, {
    required Map<String, int> cocktailMisses,
    required Map<String, int> cocktailCorrects,
    required Map<String, int> highConfidenceMisses,
    required Map<String, int> questionTypeMisses,
    required Map<String, int> exposureByCocktail,
  }) {
    final cocktailId = question.cocktailId;
    final missCount = cocktailMisses[cocktailId] ?? 0;
    final correctCount = cocktailCorrects[cocktailId] ?? 0;
    final highConfidenceMissCount = highConfidenceMisses[cocktailId] ?? 0;
    final typeMissCount =
        questionTypeMisses['$cocktailId|${question.kind.name}'] ?? 0;
    final exposure = exposureByCocktail[cocktailId] ?? 0;
    final ingredientCostPriority = _questionCostPriority(question);
    return 10 +
        (missCount * 8) +
        (highConfidenceMissCount * 5) +
        (typeMissCount * 4) +
        ingredientCostPriority +
        min<int>(exposure, 60) -
        (correctCount * 3);
  }

  int _questionCostPriority(QuizQuestion question) {
    final ingredientName = (question.ingredientName ?? '').trim();
    if (ingredientName.isEmpty) {
      return 0;
    }
    final normalizedKey = BatchGraphResolver.normalizeKey(ingredientName);
    final ingredient = _ingredientsByName[normalizedKey];
    if (question.ingredientReferenceType == IngredientReferenceType.batch) {
      final costPerMl = VarianceMath.batchCostPerMl(
        ingredientName,
        _visibleBatches,
        _ingredientsByName,
      );
      final weighted = costPerMl * (question.correctMeasureMl ?? 0);
      return (weighted * 10).round();
    }
    final weighted = (ingredient?.costPerMl ?? 0) * (question.correctMeasureMl ?? 0);
    return (weighted * 10).round();
  }

  List<QuizQuestion> _buildMeasureQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
    Set<String>? allowedIngredientNames,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      final prioritizedIngredients = recipe.ingredients
          .where((item) => item.measureMl != null)
          .toList()
        ..sort(
          (a, b) => _quizIngredientPriorityScore(
            recipe,
            b,
          ).compareTo(_quizIngredientPriorityScore(recipe, a)),
        );
      for (final ingredient in prioritizedIngredients.take(2)) {
        final normalizedIngredient = BatchGraphResolver.normalizeKey(
          ingredient.ingredientName,
        );
        if (_isLowPriorityQuizIngredient(ingredient.ingredientName)) {
          continue;
        }
        if (allowedIngredientNames != null) {
          final matchesConcern = ingredient.isBatchReference
              ? BatchGraphResolver.decomposeCocktailIngredient(
                  ingredient,
                  batches: _visibleBatches,
                  ingredientsByName: _ingredientsByName,
                ).components.any(
                  (component) => allowedIngredientNames.contains(
                    BatchGraphResolver.normalizeKey(component.ingredientName),
                  ),
                )
              : allowedIngredientNames.contains(normalizedIngredient);
          if (!matchesConcern) {
            continue;
          }
        }
        final options = _measureOptions(
          correctAmountMl: ingredient.measureMl!,
          ingredientName: ingredient.ingredientName,
          recipes: pool,
          preferredCategory: recipe.category,
        );
        if (options.length < 2) {
          continue;
        }
        final key = '${recipe.id}|measure|$normalizedIngredient';
        if (!seenKeys.add(key)) {
          continue;
        }
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.ingredientMeasure,
            prompt:
                'How much ${ingredient.ingredientName} is in ${recipe.name}?',
            options: options,
            correctAnswer: '${ingredient.measureMl!.toStringAsFixed(0)}ml',
            explanation: _measureExplanation(
              recipeName: recipe.name,
              ingredientName: ingredient.ingredientName,
              correctMeasureMl: ingredient.measureMl!,
            ),
            ingredientName: ingredient.ingredientName,
            correctMeasureMl: ingredient.measureMl,
            ingredientReferenceType: ingredient.referenceType,
            linkedBatchId: ingredient.linkedBatchId,
          ),
        );
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildBatchAmountQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
    Set<String>? allowedIngredientNames,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      for (final batchIngredient in recipe.ingredients.where(
        (item) => item.isBatchReference && item.measureMl != null,
      )) {
        if (allowedIngredientNames != null) {
          final components = BatchGraphResolver.decomposeCocktailIngredient(
            batchIngredient,
            batches: _visibleBatches,
            ingredientsByName: _ingredientsByName,
          ).components;
          final matchesConcern = components.any(
            (component) => allowedIngredientNames.contains(
              BatchGraphResolver.normalizeKey(component.ingredientName),
            ),
          );
          if (!matchesConcern) {
            continue;
          }
        }
        final options = _measureOptions(
          correctAmountMl: batchIngredient.measureMl!,
          ingredientName: batchIngredient.ingredientName,
          recipes: pool,
          preferredCategory: recipe.category,
        );
        if (options.length < 2) {
          continue;
        }
        final batchKey =
            '${recipe.id}|batch|${BatchGraphResolver.normalizeKey(batchIngredient.ingredientName)}';
        if (seenKeys.add(batchKey)) {
          questions.add(
            QuizQuestion(
              id: _nextId('question'),
              cocktailId: recipe.id,
              cocktailName: recipe.name,
              kind: QuestionKind.batchAmount,
              prompt: 'What batch amount is used in ${recipe.name}?',
              options: options,
              correctAnswer:
                  '${batchIngredient.measureMl!.toStringAsFixed(0)}ml',
              explanation: _measureExplanation(
                recipeName: recipe.name,
                ingredientName: batchIngredient.ingredientName,
                correctMeasureMl: batchIngredient.measureMl!,
              ),
              ingredientName: batchIngredient.ingredientName,
              correctMeasureMl: batchIngredient.measureMl,
              ingredientReferenceType: batchIngredient.referenceType,
              linkedBatchId: batchIngredient.linkedBatchId,
            ),
          );
        }
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildGarnishGlassQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      if (recipe.glassware.trim().isNotEmpty) {
        final options = _textOptions(
          correct: recipe.glassware,
          preferredPool: pool
              .where((item) => item.id != recipe.id && item.category == recipe.category)
              .map((item) => item.glassware),
          fallbackPool: pool.map((item) => item.glassware),
          fallbackOptions: const [
            'Coupe',
            'Martini glass',
            'Highball',
            'Wine glass',
            'Rocks glass',
          ],
        );
        if (options.length >= 2 && seenKeys.add('${recipe.id}|glassware')) {
          questions.add(
            QuizQuestion(
              id: _nextId('question'),
              cocktailId: recipe.id,
              cocktailName: recipe.name,
              kind: QuestionKind.glassware,
              prompt: 'Which glassware is used for ${recipe.name}?',
              options: options,
              correctAnswer: recipe.glassware,
              explanation:
                  '${recipe.name} should be served in ${recipe.glassware} so the presentation and serve size match the approved spec.',
              imageAssetPath: recipe.imageAssetPath,
            ),
          );
        }
      }
      if (recipe.garnish.trim().isNotEmpty) {
        final options = _textOptions(
          correct: recipe.garnish,
          preferredPool: pool
              .where((item) => item.id != recipe.id && item.category == recipe.category)
              .map((item) => item.garnish),
          fallbackPool: pool.map((item) => item.garnish),
          fallbackOptions: const [
            'Lime wedge',
            'Orange slice',
            'Mint sprig',
            'Lemon twist',
            'No garnish',
          ],
        );
        if (options.length >= 2 && seenKeys.add('${recipe.id}|garnish')) {
          questions.add(
            QuizQuestion(
              id: _nextId('question'),
              cocktailId: recipe.id,
              cocktailName: recipe.name,
              kind: QuestionKind.garnish,
              prompt: 'What garnish is listed for ${recipe.name}?',
              options: options,
              correctAnswer: recipe.garnish,
              explanation:
                  '${recipe.garnish} is the approved garnish for ${recipe.name}, helping the drink leave the bar to brand standard.',
              imageAssetPath: recipe.imageAssetPath,
            ),
          );
        }
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildMissingIngredientQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      final directIngredients = recipe.ingredients
          .where((item) => !item.isBatchReference)
          .toList();
      if (directIngredients.length < 3) {
        continue;
      }
      final rankedDirectIngredients = [...directIngredients]
        ..sort(
          (a, b) => _quizIngredientPriorityScore(
            recipe,
            b,
          ).compareTo(_quizIngredientPriorityScore(recipe, a)),
        );
      final missingIngredient = rankedDirectIngredients.firstWhere(
        (item) => !_isLowPriorityQuizIngredient(item.ingredientName),
        orElse: () => rankedDirectIngredients.first,
      );
      final shownIngredients = directIngredients
          .where((item) => item.ingredientName != missingIngredient.ingredientName)
          .where((item) => !_isLowPriorityQuizIngredient(item.ingredientName))
          .take(directIngredients.length - 1)
          .take(4)
          .map((item) => item.ingredientName)
          .join(', ');
      final options = _textOptions(
        correct: missingIngredient.ingredientName,
        preferredPool: pool
            .where((item) => item.id != recipe.id && item.category == recipe.category)
            .expand((item) => item.ingredients)
            .where((item) => !item.isBatchReference)
            .map((item) => item.ingredientName),
        fallbackPool: pool
            .expand((item) => item.ingredients)
            .where((item) => !item.isBatchReference)
            .map((item) => item.ingredientName),
        fallbackOptions: const [
          'Sugar syrup',
          'Lemon juice',
          'Lime juice',
          'Orange juice',
        ],
      );
      final key = '${recipe.id}|missing-ingredient';
      if (options.length >= 2 && seenKeys.add(key)) {
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.missingIngredient,
            prompt: 'Which ingredient is missing from $shownIngredients in ${recipe.name}?',
            options: options,
            correctAnswer: missingIngredient.ingredientName,
            explanation:
                '${missingIngredient.ingredientName} completes the approved ${recipe.name} spec. Missing it changes the build and the guest experience.',
          ),
        );
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildIngredientChoiceQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      final directIngredients = recipe.ingredients
          .where((item) => !item.isBatchReference)
          .toList();
      if (directIngredients.length < 2) {
        continue;
      }
      final rankedDirectIngredients = [...directIngredients]
        ..sort(
          (a, b) => _quizIngredientPriorityScore(
            recipe,
            b,
          ).compareTo(_quizIngredientPriorityScore(recipe, a)),
        );
      final correctIngredient = rankedDirectIngredients.firstWhere(
        (item) => !_isLowPriorityQuizIngredient(item.ingredientName),
        orElse: () => rankedDirectIngredients.first,
      );
      final options = _textOptions(
        correct: correctIngredient.ingredientName,
        preferredPool: pool
            .where((item) => item.id != recipe.id && item.category == recipe.category)
            .expand((item) => item.ingredients)
            .where((item) => !item.isBatchReference)
            .map((item) => item.ingredientName),
        fallbackPool: pool
            .expand((item) => item.ingredients)
            .where((item) => !item.isBatchReference)
            .map((item) => item.ingredientName),
        fallbackOptions: const [
          'Lime juice',
          'Lemon juice',
          'Sugar syrup',
          'Simple syrup',
          'Orange juice',
        ],
      );
      final promptIngredients = directIngredients
          .where((item) => item.ingredientName != correctIngredient.ingredientName)
          .where((item) => !_isLowPriorityQuizIngredient(item.ingredientName))
          .take(3)
          .map((item) => item.ingredientName)
          .join(', ');
      final key = '${recipe.id}|ingredient-choice';
      if (options.length >= 2 && seenKeys.add(key)) {
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.ingredientChoice,
            prompt:
                'Which ingredient completes ${recipe.name} alongside $promptIngredients?',
            options: options,
            correctAnswer: correctIngredient.ingredientName,
            explanation:
                '${correctIngredient.ingredientName} is part of the approved ${recipe.name} spec. Missing it changes the intended balance and serve consistency.',
            ingredientName: correctIngredient.ingredientName,
          ),
        );
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildCocktailIdentificationQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      final ingredientList = recipe.ingredients
          .where((item) => !_isLowPriorityQuizIngredient(item.ingredientName))
          .take(4)
          .map((item) => item.measureMl == null
              ? item.ingredientName
              : '${item.measureMl!.toStringAsFixed(0)}ml ${item.ingredientName}')
          .join(', ');
      if (ingredientList.trim().isEmpty) {
        continue;
      }
      final options = _textOptions(
        correct: recipe.name,
        preferredPool: pool
            .where((item) => item.id != recipe.id && item.category == recipe.category)
            .map((item) => item.name),
        fallbackPool: pool.where((item) => item.id != recipe.id).map((item) => item.name),
        fallbackOptions: const ['Margarita', 'Daiquiri', 'Negroni', 'Mojito'],
      );
      final key = '${recipe.id}|cocktail-identification';
      if (options.length >= 2 && seenKeys.add(key)) {
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.cocktailByIngredient,
            prompt: 'Which cocktail matches this spec: $ingredientList?',
            options: options,
            correctAnswer: recipe.name,
            explanation:
                'Those ingredients identify ${recipe.name}. Recognising the spec quickly helps service stay accurate under pressure.',
          ),
        );
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildMethodQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      if (recipe.method.trim().isEmpty) {
        continue;
      }
      final options = _textOptions(
        correct: recipe.method,
        preferredPool: pool
            .where((item) => item.id != recipe.id && item.category == recipe.category)
            .map((item) => item.method),
        fallbackPool: pool.where((item) => item.id != recipe.id).map((item) => item.method),
        fallbackOptions: const ['Built', 'Shaken', 'Stirred', 'Layered'],
      );
      final key = '${recipe.id}|method';
      if (options.length >= 2 && seenKeys.add(key)) {
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.method,
            prompt: 'Which build style is approved for ${recipe.name}?',
            options: options,
            correctAnswer: recipe.method,
            explanation:
                '${recipe.name} is prepared using the ${recipe.method} method in the approved spec. Changing the build style changes dilution, temperature, and texture.',
          ),
        );
      }
    }
    return questions;
  }

  List<QuizQuestion> _buildMethodOrderQuestions({
    required List<CocktailRecipe> recipes,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      final steps = _methodStepsForRecipe(recipe);
      if (steps.length < 3) {
        continue;
      }
      final currentStep = steps[0];
      final nextStep = steps[1];
      final options = _textOptions(
        correct: nextStep,
        preferredPool: steps.skip(2),
        fallbackPool: const [
          'Add ice',
          'Shake hard',
          'Fine strain',
          'Top and garnish',
          'Serve immediately',
        ],
        fallbackOptions: const [
          'Add ice',
          'Shake hard',
          'Fine strain',
          'Top and garnish',
          'Serve immediately',
        ],
      );
      final key = '${recipe.id}|method-order';
      if (options.length >= 2 && seenKeys.add(key)) {
        questions.add(
          QuizQuestion(
            id: _nextId('question'),
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            kind: QuestionKind.methodOrder,
            prompt: 'For ${recipe.name}, what comes next after "$currentStep"?',
            options: options,
            correctAnswer: nextStep,
            explanation:
                'Following the approved order for ${recipe.name} keeps dilution, temperature, and presentation consistent during service.',
          ),
        );
      }
    }
    return questions;
  }

  List<String> _measureOptions({
    required double correctAmountMl,
    required String ingredientName,
    required List<CocktailRecipe> recipes,
    required String preferredCategory,
  }) {
    final normalizedIngredient = BatchGraphResolver.normalizeKey(ingredientName);
    final candidateValues = <double>{correctAmountMl};
    final actualMeasures = <double>{};

    Iterable<RecipeIngredient> matchingIngredients(Iterable<CocktailRecipe> source) {
      return source.expand((recipe) => recipe.ingredients).where(
        (item) =>
            item.measureMl != null &&
            BatchGraphResolver.normalizeKey(item.ingredientName) ==
                normalizedIngredient,
      );
    }

    for (final item in matchingIngredients(
      recipes.where((recipe) => recipe.category == preferredCategory),
    )) {
      actualMeasures.add(item.measureMl!);
    }
    for (final item in matchingIngredients(recipes)) {
      actualMeasures.add(item.measureMl!);
    }
    candidateValues.addAll(actualMeasures);
    candidateValues.addAll({
      (correctAmountMl - 10).clamp(5, 250).toDouble(),
      (correctAmountMl - 5).clamp(5, 250).toDouble(),
      (correctAmountMl + 5).clamp(5, 250).toDouble(),
      (correctAmountMl + 10).clamp(5, 250).toDouble(),
    });
    candidateValues.addAll(const [15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 100, 125, 150]);

    int compareByCloseness(double a, double b) {
        final distance = (a - correctAmountMl).abs().compareTo(
          (b - correctAmountMl).abs(),
        );
        if (distance != 0) {
          return distance;
        }
        return a.compareTo(b);
    }

    final rankedActualDistractors = actualMeasures
        .where((value) => value != correctAmountMl)
        .toList()
      ..sort(compareByCloseness);
    final rankedSyntheticDistractors = candidateValues
        .where(
          (value) => value != correctAmountMl && !actualMeasures.contains(value),
        )
        .toList()
      ..sort(compareByCloseness);

    final selected = <double>{correctAmountMl};
    for (final value in [...rankedActualDistractors, ...rankedSyntheticDistractors]) {
      selected.add(value);
      if (selected.length == 4) {
        break;
      }
    }

    final values = selected.toList()..sort();
    return values.map((value) => '${value.toStringAsFixed(0)}ml').toList();
  }

  List<String> _textOptions({
    required String correct,
    required Iterable<String> preferredPool,
    required Iterable<String> fallbackPool,
    required List<String> fallbackOptions,
  }) {
    final options = <String>{correct};
    void addFrom(Iterable<String> source) {
      for (final value in source) {
        final normalized = value.trim();
        if (normalized.isEmpty || normalized == correct) {
          continue;
        }
        options.add(normalized);
        if (options.length == 4) {
          return;
        }
      }
    }
    addFrom(preferredPool);
    if (options.length < 4) {
      addFrom(fallbackPool);
    }
    if (options.length < 4) {
      addFrom(fallbackOptions);
    }
    return options.toList().take(4).toList();
  }

  double _quizIngredientPriorityScore(
    CocktailRecipe recipe,
    RecipeIngredient ingredient,
  ) {
    final normalizedName = BatchGraphResolver.normalizeKey(
      ingredient.ingredientName,
    );
    final measureMl = ingredient.measureMl ?? 0;
    final costPerMl = ingredient.isBatchReference
        ? VarianceMath.batchCostPerMl(
            ingredient.linkedBatchId ?? ingredient.ingredientName,
            _visibleBatches,
            _ingredientsByName,
          )
        : (_ingredientsByName[normalizedName]?.costPerMl ?? 0);
    final lowPriorityPenalty = _isLowPriorityQuizIngredient(ingredient.ingredientName)
        ? 1000.0
        : 0.0;
    return (costPerMl * measureMl) -
        lowPriorityPenalty +
        ((recipe.priceGbp ?? 0) * 0.01);
  }

  bool _isLowPriorityQuizIngredient(String ingredientName) {
    final normalized = BatchGraphResolver.normalizeKey(ingredientName);
    return const {
      'soda water',
      'tonic water',
      'lemonade',
      'cola',
      'ginger beer',
      'ginger ale',
      'water',
    }.contains(normalized);
  }

  String _measureExplanation({
    required String recipeName,
    required String ingredientName,
    required double correctMeasureMl,
  }) {
    final measureLabel = '${correctMeasureMl.toStringAsFixed(0)}ml';
    return '$measureLabel of $ingredientName is the approved measure for $recipeName. A smaller pour weakens balance, while a larger pour increases cost and consistency risk.';
  }

  List<String> _methodStepsForRecipe(CocktailRecipe recipe) {
    final normalizedMethod = recipe.method.trim().toLowerCase();
    if (normalizedMethod.contains('shake')) {
      return const [
        'Build ingredients in the tin',
        'Add ice and shake hard',
        'Strain into the correct glass',
        'Finish with the approved garnish',
      ];
    }
    if (normalizedMethod.contains('stir')) {
      return const [
        'Add ingredients to the mixing vessel',
        'Add ice and stir to chill',
        'Strain into the correct glass',
        'Finish with the approved garnish',
      ];
    }
    if (normalizedMethod.contains('build')) {
      return const [
        'Build ingredients into the glass',
        'Add ice if the serve requires it',
        'Top or lengthen as specified',
        'Finish with the approved garnish',
      ];
    }
    if (normalizedMethod.contains('layer')) {
      return const [
        'Add the base ingredients',
        'Carefully layer the next component',
        'Check the visual presentation',
        'Serve with the approved garnish',
      ];
    }
    return const [
      'Build ingredients to spec',
      'Chill or dilute using the approved method',
      'Pour into the correct glass',
      'Finish with the approved garnish',
    ];
  }

  double? _parseMeasure(String answer) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(answer);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-$_idCounter';
  }

  WeeklyConcernSession? _findMatchingWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final concernKey =
        concerns.map((item) => item.ingredientName.toLowerCase()).toList()
          ..sort();
    for (final session in _weeklySessions) {
      final sessionKey =
          session.concerns
              .map((item) => item.ingredientName.toLowerCase())
              .toList()
            ..sort();
      if (_sameDay(session.weekStart, weekStart) &&
          session.label.trim().toLowerCase() == label.trim().toLowerCase() &&
          '$sessionKey' == '$concernKey') {
        return session;
      }
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  RecipeImportResult _normalizeImportResult(RecipeImportResult result) {
    final linkedDrafts = BatchGraphResolver.linkDrafts(result.drafts);
    return RecipeImportResult(
      sourceName: result.sourceName,
      drafts: linkedDrafts,
      warnings: result.warnings,
      requiresOcr: result.requiresOcr,
      rawText: result.rawText,
      pageCount: result.pageCount,
    );
  }
}
