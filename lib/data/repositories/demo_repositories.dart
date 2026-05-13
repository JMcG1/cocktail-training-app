import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/pdf_recipe_extractor.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

class LocalTrainingRepository implements TrainingRepository {
  LocalTrainingRepository()
      : _textParser = RecipeTextParser(),
        _pdfExtractor = PdfRecipeExtractor(RecipeTextParser());

  final RecipeTextParser _textParser;
  final PdfRecipeExtractor _pdfExtractor;
  final List<Ingredient> _ingredients = [];
  final List<CocktailRecipe> _recipes = [];
  final List<BatchRecipe> _batches = [];
  final List<WeeklyConcernSession> _weeklySessions = [];
  final List<QuizSession> _quizSessions = [];
  final List<QuizAttempt> _quizAttempts = [];
  RecipeImportResult? _latestImportResult;
  int _idCounter = 0;

  @override
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  @override
  List<CocktailRecipe> get recipes => List.unmodifiable(_recipes);

  @override
  List<BatchRecipe> get batches => List.unmodifiable(_batches);

  @override
  List<WeeklyConcernSession> get weeklySessions =>
      List.unmodifiable(_weeklySessions.reversed);

  @override
  List<QuizSession> get quizSessions => List.unmodifiable(_quizSessions.reversed);

  @override
  List<QuizAttempt> get quizAttempts => List.unmodifiable(_quizAttempts.reversed);

  @override
  RecipeImportResult? get latestImportResult => _latestImportResult;

  @override
  Future<void> initialize() async {
    _weeklySessions.clear();
    _quizAttempts.clear();
    _latestImportResult = null;
  }

  @override
  void configureVenue(String venueId) {}

  @override
  Future<void> loadManagerData() async {}

  @override
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _latestImportResult =
        _normalizeImportResult(_pdfExtractor.extract(bytes: bytes, fileName: fileName));
    return _latestImportResult!;
  }

  @override
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  }) {
    _latestImportResult = _normalizeImportResult(_textParser.parseImportText(
      source: text,
      sourceName: sourceName,
    ));
    return _latestImportResult!;
  }

  @override
  void clearImportPreview() {
    _latestImportResult = null;
  }

  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    final approvedBatches = drafts
        .where((draft) => draft.status == RecipeDraftStatus.approved && draft.isBatch)
        .map((draft) => draft.toBatchRecipe().copyWith(isApproved: true))
        .toList();
    for (final batch in approvedBatches) {
      saveBatch(batch);
      for (final ingredient in batch.ingredients.where((item) => !item.isBatchReference)) {
        _ensureIngredientExists(ingredient.ingredientName);
      }
    }

    final approvedDrafts = drafts
        .where((draft) => draft.status == RecipeDraftStatus.approved && !draft.isBatch)
        .map((draft) => draft.toRecipe().copyWith(isApproved: true))
        .toList();
    final linkedApprovedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: approvedDrafts,
      batches: _batches,
    );
    for (final recipe in linkedApprovedRecipes) {
      saveRecipe(recipe);
      for (final ingredient in recipe.ingredients.where((item) => !item.isBatchReference)) {
        _ensureIngredientExists(ingredient.ingredientName);
      }
    }
    final remainingDrafts = drafts
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .toList();
    _latestImportResult = remainingDrafts.isEmpty
        ? null
        : _normalizeImportResult(RecipeImportResult(
            sourceName: _latestImportResult?.sourceName ?? 'Import review',
            drafts: remainingDrafts,
            warnings: _latestImportResult?.warnings ?? const [],
            requiresOcr: false,
            rawText: _latestImportResult?.rawText ?? '',
            pageCount: _latestImportResult?.pageCount ?? 0,
          ));
  }

  @override
  void saveIngredient(Ingredient ingredient) {
    final index = _ingredients.indexWhere(
      (item) => item.id == ingredient.id || item.name.toLowerCase() == ingredient.name.toLowerCase(),
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
      ingredients: recipe.ingredients
          .where((item) => item.ingredientName.trim().isNotEmpty)
          .map(
            (item) => item.copyWith(
              ingredientName: item.ingredientName.trim(),
            ),
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
        .map((item) => item.copyWith(ingredientName: item.ingredientName.trim()))
        .toList();
    final linkedIngredients = normalizedIngredients
        .map(
          (item) => BatchGraphResolver.linkIngredientToBatch(
            ingredient: item,
            batchIndex: BatchGraphResolver.buildBatchIndex(_batches.where((existing) => existing.id != batch.id)),
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
    final relinked = BatchGraphResolver.linkCocktailsToBatches(cocktails: _recipes, batches: _batches);
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
    final concernNames = concerns.map((item) => item.ingredientName.toLowerCase()).toSet();
    final targetIds = _approvedRecipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: concernNames,
            batches: _batches,
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
      (record) => record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
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
    final weeklySession = _weeklySessions.firstWhere((session) => session.id == weekId);
    final targetRecipes = _approvedRecipes
        .where((recipe) => weeklySession.targetCocktailIds.contains(recipe.id))
        .toList();
    final concernNames = weeklySession.concerns
        .map((item) => BatchGraphResolver.normalizeKey(item.ingredientName))
        .toSet();
    final measureQuestions = _buildMeasureQuestions(
      recipes: targetRecipes,
      allowedIngredientNames: concernNames,
    );
    final secondaryQuestions = _buildSecondaryQuestions(
      recipes: targetRecipes,
      pool: targetRecipes,
    );

    final prioritizedQuestions = [
      ..._shuffleQuestions(measureQuestions, bartenderName),
      ..._shuffleQuestions(secondaryQuestions, '$bartenderName-secondary'),
    ];

    final quiz = QuizSession(
      id: _nextId('quiz'),
      title: '${weeklySession.label} targeted stock quiz',
      bartenderName: bartenderName,
      kind: QuizKind.stockVariance,
      isActive: true,
      createdAt: DateTime.now(),
      questions: prioritizedQuestions.take(min(10, prioritizedQuestions.length)).toList(),
      weekId: weeklySession.id,
    );
    _quizSessions.add(quiz);
    final sessionIndex = _weeklySessions.indexWhere((session) => session.id == weekId);
    _weeklySessions[sessionIndex] = weeklySession.copyWith(
      quizSessionIds: [...weeklySession.quizSessionIds, quiz.id],
    );
    return quiz;
  }

  @override
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
  }) {
    final allowedIds = focusRecipeIds?.toSet();
    final recipePool = allowedIds == null
        ? _approvedRecipes
        : _approvedRecipes.where((recipe) => allowedIds.contains(recipe.id)).toList();
    final questions = [
      ..._buildMeasureQuestions(recipes: recipePool),
      ..._buildSecondaryQuestions(recipes: recipePool, pool: _approvedRecipes),
    ];

    final quiz = QuizSession(
      id: _nextId('quiz'),
      title: 'Practice quiz',
      bartenderName: bartenderName,
      kind: QuizKind.practice,
      isActive: true,
      createdAt: DateTime.now(),
      questions: _takeTen(questions, bartenderName),
    );
    _quizSessions.add(quiz);
    return quiz;
  }

  List<CocktailRecipe> get _approvedRecipes =>
      _recipes.where((recipe) => recipe.isApproved).toList();

  Map<String, Ingredient> get _ingredientsByName => {
        for (final ingredient in _ingredients)
          BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
      };

  @override
  QuizAttempt submitQuizAttempt({
    required String sessionId,
    required String bartenderName,
    required Map<String, String> answers,
  }) {
    final existingAttempt = _quizAttempts.cast<QuizAttempt?>().firstWhere(
          (attempt) =>
              attempt != null &&
              attempt.sessionId == sessionId &&
              attempt.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => null,
        );
    if (existingAttempt != null) {
      return existingAttempt;
    }
    final sessionIndex = _quizSessions.indexWhere((session) => session.id == sessionId);
    final session = _quizSessions[sessionIndex];
    if (!session.isActive) {
      throw Exception('This quiz session is no longer active. Ask your manager for a fresh link.');
    }
    final weeklySession = session.weekId == null
        ? null
        : _weeklySessions.firstWhere((item) => item.id == session.weekId);
    final sales = weeklySession?.bartenderSales.firstWhere(
          (record) => record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => BartenderWeeklySales(bartenderName: bartenderName, entries: const []),
        ) ??
        BartenderWeeklySales(bartenderName: bartenderName, entries: const []);
    final quantityByCocktail = {
      for (final entry in sales.entries) entry.cocktailId: entry.quantitySold,
    };
    final ingredientsByName = {
      for (final ingredient in _ingredients)
        BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
    };

    final responses = session.questions.map((question) {
      final selectedAnswer = answers[question.id] ?? '';
      final isCorrect = selectedAnswer == question.correctAnswer;
      final quantitySold = quantityByCocktail[question.cocktailId] ?? 0;
      double? deltaMl;
      if (question.kind == QuestionKind.ingredientMeasure &&
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
        deltaMl: deltaMl,
      );
    }).toList();

    final attempt = VarianceMath.buildAttempt(
      attemptId: _nextId('attempt'),
      sessionId: session.id,
      weekId: session.weekId,
      bartenderName: bartenderName,
      responses: responses,
      ingredientsByName: ingredientsByName,
      batches: _batches,
    );

    _quizAttempts.add(attempt);
    _quizSessions[sessionIndex] = session.copyWith(isActive: false);
    return attempt;
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
    final index = _quizSessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) {
      return;
    }
    _quizSessions[index] = _quizSessions[index].copyWith(isActive: false);
  }

  void _ensureIngredientExists(String name) {
    final existing = _ingredients.any(
      (ingredient) => ingredient.name.toLowerCase() == name.toLowerCase(),
    );
    if (!existing) {
      _ingredients.add(
        Ingredient(
          id: _nextId('ingredient'),
          name: name,
          bottleSizeMl: 700,
          bottleCost: 0,
        ),
      );
    }
  }

  List<QuizQuestion> _takeTen(List<QuizQuestion> questions, String seed) {
    if (questions.isEmpty) {
      return const [];
    }
    final shuffled = _shuffleQuestions(questions, seed);
    return shuffled.take(min(10, shuffled.length)).toList();
  }

  List<QuizQuestion> _shuffleQuestions(List<QuizQuestion> questions, String seed) {
    final random = Random(seed.hashCode);
    return [...questions]..shuffle(random);
  }

  List<QuizQuestion> _buildMeasureQuestions({
    required List<CocktailRecipe> recipes,
    Set<String>? allowedIngredientNames,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      for (final ingredient in recipe.ingredients.where((item) => item.measureMl != null)) {
        final normalizedIngredient = BatchGraphResolver.normalizeKey(ingredient.ingredientName);
        if (allowedIngredientNames != null) {
          final matchesConcern = ingredient.isBatchReference
              ? BatchGraphResolver.decomposeCocktailIngredient(
                  ingredient,
                  batches: _batches,
                  ingredientsByName: _ingredientsByName,
                ).components.any(
                  (component) =>
                      allowedIngredientNames.contains(
                        BatchGraphResolver.normalizeKey(component.ingredientName),
                      ),
                )
              : allowedIngredientNames.contains(normalizedIngredient);
          if (!matchesConcern) {
            continue;
          }
        }
        final options = _measureOptions(ingredient.measureMl!);
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
            prompt: 'How much ${ingredient.ingredientName} is in ${recipe.name}?',
            options: options,
            correctAnswer: '${ingredient.measureMl!.toStringAsFixed(0)}ml',
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

  List<QuizQuestion> _buildSecondaryQuestions({
    required List<CocktailRecipe> recipes,
    required List<CocktailRecipe> pool,
  }) {
    final questions = <QuizQuestion>[];
    final seenKeys = <String>{};
    for (final recipe in recipes) {
      if (recipe.glassware.trim().isNotEmpty) {
        final options = _textOptions(recipe.glassware, pool.map((item) => item.glassware));
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
            ),
          );
        }
      }
      if (recipe.garnish.trim().isNotEmpty) {
        final options = _textOptions(recipe.garnish, pool.map((item) => item.garnish));
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
            ),
          );
        }
      }
      if (recipe.method.trim().isNotEmpty) {
        final options = _textOptions(recipe.method, pool.map((item) => item.method));
        if (options.length >= 2 && seenKeys.add('${recipe.id}|method')) {
          questions.add(
            QuizQuestion(
              id: _nextId('question'),
              cocktailId: recipe.id,
              cocktailName: recipe.name,
              kind: QuestionKind.method,
              prompt: 'Which method matches ${recipe.name}?',
              options: options,
              correctAnswer: recipe.method,
            ),
          );
        }
      }
    }
    return questions;
  }

  List<String> _measureOptions(double correctAmountMl) {
    final values = <double>{
      correctAmountMl,
      (correctAmountMl - 10).clamp(5, 250).toDouble(),
      (correctAmountMl - 5).clamp(5, 250).toDouble(),
      (correctAmountMl + 5).clamp(5, 250).toDouble(),
      (correctAmountMl + 10).clamp(5, 250).toDouble(),
    }.toList()
      ..sort();
    return values.map((value) => '${value.toStringAsFixed(0)}ml').take(4).toList();
  }

  List<String> _textOptions(String correct, Iterable<String> pool) {
    final options = <String>{correct};
    for (final value in pool) {
      final normalized = value.trim();
      if (normalized.isEmpty || normalized == correct) {
        continue;
      }
      options.add(normalized);
      if (options.length == 4) {
        break;
      }
    }
    if (options.length < 4) {
      options.add('Needs review');
    }
    return options.toList().take(4).toList();
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
    final concernKey = concerns
        .map((item) => item.ingredientName.toLowerCase())
        .toList()
      ..sort();
    for (final session in _weeklySessions) {
      final sessionKey = session.concerns
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
