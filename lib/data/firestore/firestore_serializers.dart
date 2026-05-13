import '../../domain/models/models.dart';

class FirestoreSerializers {
  const FirestoreSerializers._();

  static Map<String, dynamic> ingredientToMap(Ingredient ingredient) {
    return {
      'name': ingredient.name,
      'bottleSizeMl': ingredient.bottleSizeMl,
      'bottleCost': ingredient.bottleCost,
      'costPerMl': ingredient.costPerMl,
    };
  }

  static Ingredient ingredientFromMap(String id, Map<String, dynamic> data) {
    return Ingredient(
      id: id,
      name: data['name'] as String? ?? '',
      bottleSizeMl: (data['bottleSizeMl'] as num?)?.toDouble() ?? 0,
      bottleCost: (data['bottleCost'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, dynamic> recipeIngredientToMap(RecipeIngredient ingredient) {
    return {
      'ingredientName': ingredient.ingredientName,
      'measureMl': ingredient.measureMl,
      'preparationNote': ingredient.preparationNote,
    };
  }

  static RecipeIngredient recipeIngredientFromMap(Map<String, dynamic> data) {
    return RecipeIngredient(
      ingredientName: data['ingredientName'] as String? ?? '',
      measureMl: (data['measureMl'] as num?)?.toDouble(),
      preparationNote: data['preparationNote'] as String?,
    );
  }

  static Map<String, dynamic> recipeToMap(CocktailRecipe recipe) {
    return {
      'name': recipe.name,
      'category': recipe.category,
      'glassware': recipe.glassware,
      'garnish': recipe.garnish,
      'method': recipe.method,
      'notes': recipe.notes,
      'sourceLabel': recipe.sourceLabel,
      'needsReview': recipe.needsReview,
      'reviewFlags': recipe.reviewFlags,
      'isApproved': recipe.isApproved,
      'wasManuallyReviewed': recipe.wasManuallyReviewed,
      'ingredients': recipe.ingredients.map(recipeIngredientToMap).toList(),
    };
  }

  static CocktailRecipe recipeFromMap(String id, Map<String, dynamic> data) {
    final ingredients = (data['ingredients'] as List<dynamic>? ?? const [])
        .map((item) => recipeIngredientFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    return CocktailRecipe(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      glassware: data['glassware'] as String? ?? '',
      garnish: data['garnish'] as String? ?? '',
      method: data['method'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      ingredients: ingredients,
      sourceLabel: data['sourceLabel'] as String? ?? '',
      needsReview: data['needsReview'] as bool? ?? false,
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const []).cast<String>(),
      isApproved: data['isApproved'] as bool? ?? true,
      wasManuallyReviewed: data['wasManuallyReviewed'] as bool? ?? true,
    );
  }

  static Map<String, dynamic> draftToMap(RecipeImportDraft draft) {
    return {
      'sourceLabel': draft.sourceLabel,
      'pageLabel': draft.pageLabel,
      'name': draft.name,
      'category': draft.category,
      'glassware': draft.glassware,
      'garnish': draft.garnish,
      'method': draft.method,
      'notes': draft.notes,
      'ingredients': draft.ingredients.map(recipeIngredientToMap).toList(),
      'reviewFlags': draft.reviewFlags,
      'status': draft.status.name,
      'wasManuallyReviewed': draft.wasManuallyReviewed,
    };
  }

  static RecipeImportDraft draftFromMap(String id, Map<String, dynamic> data) {
    final ingredients = (data['ingredients'] as List<dynamic>? ?? const [])
        .map((item) => recipeIngredientFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    return RecipeImportDraft(
      id: id,
      sourceLabel: data['sourceLabel'] as String? ?? '',
      pageLabel: data['pageLabel'] as String? ?? '',
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      glassware: data['glassware'] as String? ?? '',
      garnish: data['garnish'] as String? ?? '',
      method: data['method'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      ingredients: ingredients,
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const []).cast<String>(),
      status: _recipeDraftStatusFromName(data['status'] as String?),
      wasManuallyReviewed: data['wasManuallyReviewed'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> stockConcernToMap(StockConcernItem concern) {
    return {
      'ingredientName': concern.ingredientName,
      'amountShortMl': concern.amountShortMl,
      'estimatedImpact': concern.estimatedImpact,
      'notes': concern.notes,
    };
  }

  static StockConcernItem stockConcernFromMap(Map<String, dynamic> data) {
    return StockConcernItem(
      ingredientName: data['ingredientName'] as String? ?? '',
      amountShortMl: (data['amountShortMl'] as num?)?.toDouble(),
      estimatedImpact: (data['estimatedImpact'] as num?)?.toDouble(),
      notes: data['notes'] as String?,
    );
  }

  static Map<String, dynamic> salesEntryToMap(BartenderSalesEntry entry) {
    return {
      'cocktailId': entry.cocktailId,
      'cocktailName': entry.cocktailName,
      'quantitySold': entry.quantitySold,
    };
  }

  static BartenderSalesEntry salesEntryFromMap(Map<String, dynamic> data) {
    return BartenderSalesEntry(
      cocktailId: data['cocktailId'] as String? ?? '',
      cocktailName: data['cocktailName'] as String? ?? '',
      quantitySold: (data['quantitySold'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, dynamic> bartenderSalesToMap(
    String weekId,
    BartenderWeeklySales sales,
  ) {
    return {
      'weekId': weekId,
      'bartenderName': sales.bartenderName,
      'entries': sales.entries.map(salesEntryToMap).toList(),
    };
  }

  static BartenderWeeklySales bartenderSalesFromMap(Map<String, dynamic> data) {
    final entries = (data['entries'] as List<dynamic>? ?? const [])
        .map((item) => salesEntryFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    return BartenderWeeklySales(
      bartenderName: data['bartenderName'] as String? ?? '',
      entries: entries,
    );
  }

  static Map<String, dynamic> weeklySessionToMap(WeeklyConcernSession session) {
    return {
      'label': session.label,
      'weekStart': session.weekStart.toIso8601String(),
      'concerns': session.concerns.map(stockConcernToMap).toList(),
      'targetCocktailIds': session.targetCocktailIds,
      'quizSessionIds': session.quizSessionIds,
    };
  }

  static WeeklyConcernSession weeklySessionFromMap(
    String id,
    Map<String, dynamic> data, {
    required List<BartenderWeeklySales> bartenderSales,
  }) {
    final concerns = (data['concerns'] as List<dynamic>? ?? const [])
        .map((item) => stockConcernFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    return WeeklyConcernSession(
      id: id,
      label: data['label'] as String? ?? '',
      weekStart: DateTime.tryParse(data['weekStart'] as String? ?? '') ?? DateTime.now(),
      concerns: concerns,
      targetCocktailIds: (data['targetCocktailIds'] as List<dynamic>? ?? const []).cast<String>(),
      bartenderSales: bartenderSales,
      quizSessionIds: (data['quizSessionIds'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  static Map<String, dynamic> quizQuestionToMap(QuizQuestion question) {
    return {
      'cocktailId': question.cocktailId,
      'cocktailName': question.cocktailName,
      'kind': question.kind.name,
      'prompt': question.prompt,
      'options': question.options,
      'correctAnswer': question.correctAnswer,
      'ingredientName': question.ingredientName,
      'correctMeasureMl': question.correctMeasureMl,
    };
  }

  static QuizQuestion quizQuestionFromMap(String id, Map<String, dynamic> data) {
    return QuizQuestion(
      id: id,
      cocktailId: data['cocktailId'] as String? ?? '',
      cocktailName: data['cocktailName'] as String? ?? '',
      kind: _questionKindFromName(data['kind'] as String?),
      prompt: data['prompt'] as String? ?? '',
      options: (data['options'] as List<dynamic>? ?? const []).cast<String>(),
      correctAnswer: data['correctAnswer'] as String? ?? '',
      ingredientName: data['ingredientName'] as String?,
      correctMeasureMl: (data['correctMeasureMl'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> quizSessionToMap(QuizSession session) {
    return {
      'title': session.title,
      'bartenderName': session.bartenderName,
      'kind': session.kind.name,
      'isActive': session.isActive,
      'createdAt': session.createdAt.toIso8601String(),
      'questions': session.questions
          .map((question) => {'id': question.id, ...quizQuestionToMap(question)})
          .toList(),
      'weekId': session.weekId,
    };
  }

  static QuizSession quizSessionFromMap(String id, Map<String, dynamic> data) {
    final questions = (data['questions'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) => quizQuestionFromMap(item['id'] as String? ?? '', item))
        .toList();
    return QuizSession(
      id: id,
      title: data['title'] as String? ?? '',
      bartenderName: data['bartenderName'] as String? ?? '',
      kind: _quizKindFromName(data['kind'] as String?),
      isActive: data['isActive'] as bool? ?? false,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
      questions: questions,
      weekId: data['weekId'] as String?,
    );
  }

  static Map<String, dynamic> varianceLineToMap(VarianceLine line) {
    return {
      'ingredientName': line.ingredientName,
      'totalMl': line.totalMl,
      'approximateValue': line.approximateValue,
      'direction': line.direction.name,
    };
  }

  static VarianceLine varianceLineFromMap(Map<String, dynamic> data) {
    return VarianceLine(
      ingredientName: data['ingredientName'] as String? ?? '',
      totalMl: (data['totalMl'] as num?)?.toDouble() ?? 0,
      approximateValue: (data['approximateValue'] as num?)?.toDouble() ?? 0,
      direction: _varianceDirectionFromName(data['direction'] as String?),
    );
  }

  static Map<String, dynamic> questionResponseToMap(QuestionResponse response) {
    return {
      'question': {'id': response.question.id, ...quizQuestionToMap(response.question)},
      'selectedAnswer': response.selectedAnswer,
      'isCorrect': response.isCorrect,
      'quantitySold': response.quantitySold,
      'deltaMl': response.deltaMl,
    };
  }

  static QuestionResponse questionResponseFromMap(Map<String, dynamic> data) {
    final questionData = Map<String, dynamic>.from(data['question'] as Map? ?? const {});
    final question = quizQuestionFromMap(questionData['id'] as String? ?? '', questionData);
    return QuestionResponse(
      question: question,
      selectedAnswer: data['selectedAnswer'] as String? ?? '',
      isCorrect: data['isCorrect'] as bool? ?? false,
      quantitySold: data['quantitySold'] as int? ?? 0,
      deltaMl: (data['deltaMl'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> quizAttemptToMap(QuizAttempt attempt) {
    return {
      'sessionId': attempt.sessionId,
      'weekId': attempt.weekId,
      'bartenderName': attempt.bartenderName,
      'submittedAt': attempt.submittedAt.toIso8601String(),
      'scorePercent': attempt.scorePercent,
      'responses': attempt.responses.map(questionResponseToMap).toList(),
      'overpourLines': attempt.overpourLines.map(varianceLineToMap).toList(),
      'underpourLines': attempt.underpourLines.map(varianceLineToMap).toList(),
      'coachingAreas': attempt.coachingAreas,
      'encouragement': attempt.encouragement,
    };
  }

  static QuizAttempt quizAttemptFromMap(String id, Map<String, dynamic> data) {
    final responses = (data['responses'] as List<dynamic>? ?? const [])
        .map((item) => questionResponseFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    final overpourLines = (data['overpourLines'] as List<dynamic>? ?? const [])
        .map((item) => varianceLineFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    final underpourLines = (data['underpourLines'] as List<dynamic>? ?? const [])
        .map((item) => varianceLineFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
    return QuizAttempt(
      id: id,
      sessionId: data['sessionId'] as String? ?? '',
      weekId: data['weekId'] as String?,
      bartenderName: data['bartenderName'] as String? ?? '',
      submittedAt: DateTime.tryParse(data['submittedAt'] as String? ?? '') ?? DateTime.now(),
      scorePercent: (data['scorePercent'] as num?)?.toInt() ?? 0,
      responses: responses,
      overpourLines: overpourLines,
      underpourLines: underpourLines,
      coachingAreas: (data['coachingAreas'] as List<dynamic>? ?? const []).cast<String>(),
      encouragement: data['encouragement'] as String? ?? '',
    );
  }

  static Map<String, dynamic> trendSummaryToMap({
    required String bartenderName,
    required int latestScorePercent,
    required double potentialVarianceValue,
  }) {
    return {
      'bartenderName': bartenderName,
      'latestScorePercent': latestScorePercent,
      'potentialVarianceValue': potentialVarianceValue,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  static RecipeDraftStatus _recipeDraftStatusFromName(String? value) {
    for (final item in RecipeDraftStatus.values) {
      if (item.name == value) {
        return item;
      }
    }
    return RecipeDraftStatus.pending;
  }

  static QuestionKind _questionKindFromName(String? value) {
    for (final item in QuestionKind.values) {
      if (item.name == value) {
        return item;
      }
    }
    return QuestionKind.ingredientMeasure;
  }

  static QuizKind _quizKindFromName(String? value) {
    for (final item in QuizKind.values) {
      if (item.name == value) {
        return item;
      }
    }
    return QuizKind.practice;
  }

  static VarianceDirection _varianceDirectionFromName(String? value) {
    for (final item in VarianceDirection.values) {
      if (item.name == value) {
        return item;
      }
    }
    return VarianceDirection.overpour;
  }
}
