import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/approved_cocktail_prices.dart';
import '../../core/utils/legacy_recipe_ids.dart';
import '../../domain/models/models.dart';

class FirestoreSerializers {
  const FirestoreSerializers._();

  static String _stringValue(Object? value, {String fallback = ''}) {
    if (value is String) {
      return value;
    }
    return fallback;
  }

  static Map<String, dynamic> ingredientToMap(Ingredient ingredient) {
    return {
      'name': ingredient.name,
      'bottleSizeMl': ingredient.bottleSizeMl,
      'bottleCost': ingredient.bottleCost,
      'costPerMl': ingredient.costPerMl,
      'isGarnish': ingredient.isGarnish,
    };
  }

  static Ingredient ingredientFromMap(String id, Map<String, dynamic> data) {
    return Ingredient(
      id: id,
      name: data['name'] as String? ?? '',
      bottleSizeMl: (data['bottleSizeMl'] as num?)?.toDouble() ?? 0,
      bottleCost: (data['bottleCost'] as num?)?.toDouble() ?? 0,
      isGarnish: data['isGarnish'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> venueInviteToMap(VenueInvite invite) {
    return {
      'venueId': invite.venueId,
      'role': invite.role.name,
      'createdBy': invite.createdBy,
      'createdAt': Timestamp.fromDate(invite.createdAt),
      'expiresAt': Timestamp.fromDate(invite.expiresAt),
      'maxUses': invite.maxUses,
      'currentUses': invite.currentUses,
      'disabled': invite.disabled,
    };
  }

  static VenueInvite venueInviteFromMap(String id, Map<String, dynamic> data) {
    return VenueInvite(
      id: id,
      venueId: _stringValue(data['venueId']),
      role: _userRoleFromName(_stringValue(data['role'])),
      createdBy: _stringValue(data['createdBy']),
      createdAt: _dateTimeFromFirestoreValue(data['createdAt']),
      expiresAt: _dateTimeFromFirestoreValue(data['expiresAt']),
      maxUses: (data['maxUses'] as num?)?.toInt() ?? 1,
      currentUses: (data['currentUses'] as num?)?.toInt() ?? 0,
      disabled: data['disabled'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> recipeIngredientToMap(
    RecipeIngredient ingredient,
  ) {
    return {
      'ingredientName': ingredient.ingredientName,
      'measureMl': ingredient.measureMl,
      'preparationNote': ingredient.preparationNote,
      'referenceType': ingredient.referenceType.name,
      'linkedBatchId': ingredient.linkedBatchId,
    };
  }

  static RecipeIngredient recipeIngredientFromMap(Map<String, dynamic> data) {
    return RecipeIngredient(
      ingredientName: data['ingredientName'] as String? ?? '',
      measureMl: (data['measureMl'] as num?)?.toDouble(),
      preparationNote: data['preparationNote'] as String?,
      referenceType: _ingredientReferenceTypeFromName(
        data['referenceType'] as String?,
      ),
      linkedBatchId: data['linkedBatchId'] as String?,
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
      'imageAssetPath': recipe.imageAssetPath,
      'missingImage': recipe.missingImage,
      'priceGbp': recipe.priceGbp,
      'ingredients': recipe.ingredients.map(recipeIngredientToMap).toList(),
    };
  }

  static Map<String, dynamic> batchRecipeToMap(BatchRecipe recipe) {
    return {
      'name': recipe.name,
      'category': recipe.category,
      'notes': recipe.notes,
      'sourceLabel': recipe.sourceLabel,
      'needsReview': recipe.needsReview,
      'reviewFlags': recipe.reviewFlags,
      'isApproved': recipe.isApproved,
      'wasManuallyReviewed': recipe.wasManuallyReviewed,
      'totalBatchVolumeMl': recipe.totalBatchVolumeMl,
      'ingredients': recipe.ingredients.map(recipeIngredientToMap).toList(),
    };
  }

  static CocktailRecipe recipeFromMap(String id, Map<String, dynamic> data) {
    final ingredients = (data['ingredients'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              recipeIngredientFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return CocktailRecipe(
      id: normalizeCocktailId(id),
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      glassware: data['glassware'] as String? ?? '',
      garnish: data['garnish'] as String? ?? '',
      method: data['method'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      ingredients: ingredients,
      sourceLabel: data['sourceLabel'] as String? ?? '',
      needsReview: data['needsReview'] as bool? ?? false,
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const [])
          .cast<String>(),
      isApproved: data['isApproved'] as bool? ?? true,
      wasManuallyReviewed: data['wasManuallyReviewed'] as bool? ?? true,
      imageAssetPath: data['imageAssetPath'] as String?,
      missingImage: data['missingImage'] as bool? ?? false,
      priceGbp:
          (data['priceGbp'] as num?)?.toDouble() ??
          approvedCocktailPriceGbpForName(data['name'] as String? ?? ''),
    );
  }

  static BatchRecipe batchRecipeFromMap(String id, Map<String, dynamic> data) {
    final ingredients = (data['ingredients'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              recipeIngredientFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return BatchRecipe(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      ingredients: ingredients,
      totalBatchVolumeMl: (data['totalBatchVolumeMl'] as num?)?.toDouble(),
      sourceLabel: data['sourceLabel'] as String? ?? '',
      needsReview: data['needsReview'] as bool? ?? false,
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const [])
          .cast<String>(),
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
      'entityType': draft.entityType.name,
      'totalBatchVolumeMl': draft.totalBatchVolumeMl,
      'priceGbp': draft.priceGbp,
    };
  }

  static RecipeImportDraft draftFromMap(String id, Map<String, dynamic> data) {
    final ingredients = (data['ingredients'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              recipeIngredientFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final entityType = _recipeEntityTypeFromName(data['entityType'] as String?);
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
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const [])
          .cast<String>(),
      status: _recipeDraftStatusFromName(data['status'] as String?),
      wasManuallyReviewed: data['wasManuallyReviewed'] as bool? ?? false,
      entityType: entityType,
      totalBatchVolumeMl: (data['totalBatchVolumeMl'] as num?)?.toDouble(),
      priceGbp:
          entityType == RecipeEntityType.cocktail
              ? ((data['priceGbp'] as num?)?.toDouble() ??
                  approvedCocktailPriceGbpForName(data['name'] as String? ?? ''))
              : (data['priceGbp'] as num?)?.toDouble(),
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
      if (entry.salesValueGbp != null) 'salesValueGbp': entry.salesValueGbp,
    };
  }

  static BartenderSalesEntry salesEntryFromMap(Map<String, dynamic> data) {
    return BartenderSalesEntry(
      cocktailId: normalizeCocktailId(data['cocktailId'] as String? ?? ''),
      cocktailName: data['cocktailName'] as String? ?? '',
      quantitySold: (data['quantitySold'] as num?)?.toInt() ?? 0,
      salesValueGbp: (data['salesValueGbp'] as num?)?.toDouble(),
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
        .map(
          (item) => salesEntryFromMap(Map<String, dynamic>.from(item as Map)),
        )
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
        .map(
          (item) => stockConcernFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return WeeklyConcernSession(
      id: id,
      label: data['label'] as String? ?? '',
      weekStart:
          DateTime.tryParse(data['weekStart'] as String? ?? '') ??
          DateTime.now(),
      concerns: concerns,
      targetCocktailIds:
          (data['targetCocktailIds'] as List<dynamic>? ?? const [])
              .cast<String>()
              .map(normalizeCocktailId)
              .toList(),
      bartenderSales: bartenderSales,
      quizSessionIds: (data['quizSessionIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
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
      'explanation': question.explanation,
      'ingredientName': question.ingredientName,
      'correctMeasureMl': question.correctMeasureMl,
      'ingredientReferenceType': question.ingredientReferenceType.name,
      'linkedBatchId': question.linkedBatchId,
      'imageAssetPath': question.imageAssetPath,
    };
  }

  static QuizQuestion quizQuestionFromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return QuizQuestion(
      id: id,
      cocktailId: normalizeCocktailId(data['cocktailId'] as String? ?? ''),
      cocktailName: data['cocktailName'] as String? ?? '',
      kind: _questionKindFromName(data['kind'] as String?),
      prompt: data['prompt'] as String? ?? '',
      options: (data['options'] as List<dynamic>? ?? const []).cast<String>(),
      correctAnswer: data['correctAnswer'] as String? ?? '',
      explanation: data['explanation'] as String? ?? '',
      ingredientName: data['ingredientName'] as String?,
      correctMeasureMl: (data['correctMeasureMl'] as num?)?.toDouble(),
      ingredientReferenceType: _ingredientReferenceTypeFromName(
        data['ingredientReferenceType'] as String?,
      ),
      linkedBatchId: data['linkedBatchId'] as String?,
      imageAssetPath: data['imageAssetPath'] as String?,
    );
  }

  static Map<String, dynamic> quizSessionToMap(QuizSession session) {
    return {
      'title': session.title,
      'bartenderName': session.bartenderName,
      'kind': session.kind.name,
      'focus': session.focus.name,
      'isActive': session.isActive,
      'createdAt': session.createdAt.toIso8601String(),
      'questions': session.questions
          .map(
            (question) => {'id': question.id, ...quizQuestionToMap(question)},
          )
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
      focus: _quizFocusFromName(data['focus'] as String?),
      isActive: data['isActive'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.now(),
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
      'sourceType': line.sourceType.name,
    };
  }

  static VarianceLine varianceLineFromMap(Map<String, dynamic> data) {
    return VarianceLine(
      ingredientName: data['ingredientName'] as String? ?? '',
      totalMl: (data['totalMl'] as num?)?.toDouble() ?? 0,
      approximateValue: (data['approximateValue'] as num?)?.toDouble() ?? 0,
      direction: _varianceDirectionFromName(data['direction'] as String?),
      sourceType: _varianceSourceTypeFromName(data['sourceType'] as String?),
    );
  }

  static Map<String, dynamic> questionResponseToMap(QuestionResponse response) {
    return {
      'question': {
        'id': response.question.id,
        ...quizQuestionToMap(response.question),
      },
      'selectedAnswer': response.selectedAnswer,
      'isCorrect': response.isCorrect,
      'quantitySold': response.quantitySold,
      'confidence': response.confidence.name,
      'deltaMl': response.deltaMl,
    };
  }

  static QuestionResponse questionResponseFromMap(Map<String, dynamic> data) {
    final questionData = Map<String, dynamic>.from(
      data['question'] as Map? ?? const {},
    );
    final question = quizQuestionFromMap(
      questionData['id'] as String? ?? '',
      questionData,
    );
    return QuestionResponse(
      question: question,
      selectedAnswer: data['selectedAnswer'] as String? ?? '',
      isCorrect: data['isCorrect'] as bool? ?? false,
      quantitySold: data['quantitySold'] as int? ?? 0,
      confidence: _quizAnswerConfidenceFromName(
        data['confidence'] as String?,
      ),
      deltaMl: (data['deltaMl'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> quizAttemptToMap(QuizAttempt attempt) {
    return {
      'sessionId': attempt.sessionId,
      'weekId': attempt.weekId,
      'userId': attempt.userId,
      'bartenderName': attempt.bartenderName,
      'startedAt': attempt.startedAt.toIso8601String(),
      'submittedAt': attempt.submittedAt.toIso8601String(),
      'scorePercent': attempt.scorePercent,
      'responses': attempt.responses.map(questionResponseToMap).toList(),
      'overpourLines': attempt.overpourLines.map(varianceLineToMap).toList(),
      'underpourLines': attempt.underpourLines.map(varianceLineToMap).toList(),
      'batchOverpourLines': attempt.batchOverpourLines
          .map(varianceLineToMap)
          .toList(),
      'batchUnderpourLines': attempt.batchUnderpourLines
          .map(varianceLineToMap)
          .toList(),
      'coachingAreas': attempt.coachingAreas,
      'encouragement': attempt.encouragement,
      'previousBestScorePercent': attempt.previousBestScorePercent,
      'improvementScorePercent': attempt.improvementScorePercent,
    };
  }

  static QuizAttempt quizAttemptFromMap(String id, Map<String, dynamic> data) {
    final responses = (data['responses'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              questionResponseFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final overpourLines = (data['overpourLines'] as List<dynamic>? ?? const [])
        .map(
          (item) => varianceLineFromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final underpourLines =
        (data['underpourLines'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  varianceLineFromMap(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
    final batchOverpourLines =
        (data['batchOverpourLines'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  varianceLineFromMap(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
    final batchUnderpourLines =
        (data['batchUnderpourLines'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  varianceLineFromMap(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
    return QuizAttempt(
      id: id,
      sessionId: data['sessionId'] as String? ?? '',
      weekId: data['weekId'] as String?,
      userId: data['userId'] as String?,
      bartenderName: data['bartenderName'] as String? ?? '',
      startedAt:
          DateTime.tryParse(data['startedAt'] as String? ?? '') ??
          DateTime.tryParse(data['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      submittedAt:
          DateTime.tryParse(data['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      scorePercent: (data['scorePercent'] as num?)?.toInt() ?? 0,
      responses: responses,
      overpourLines: overpourLines,
      underpourLines: underpourLines,
      batchOverpourLines: batchOverpourLines,
      batchUnderpourLines: batchUnderpourLines,
      coachingAreas: (data['coachingAreas'] as List<dynamic>? ?? const [])
          .cast<String>(),
      encouragement: data['encouragement'] as String? ?? '',
      previousBestScorePercent:
          (data['previousBestScorePercent'] as num?)?.toInt(),
      improvementScorePercent:
          (data['improvementScorePercent'] as num?)?.toInt(),
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

  static QuizAnswerConfidence _quizAnswerConfidenceFromName(String? value) {
    for (final item in QuizAnswerConfidence.values) {
      if (item.name == value) {
        return item;
      }
    }
    return QuizAnswerConfidence.unsure;
  }

  static QuizKind _quizKindFromName(String? value) {
    for (final item in QuizKind.values) {
      if (item.name == value) {
        return item;
      }
    }
    return QuizKind.practice;
  }

  static QuizFocus _quizFocusFromName(String? value) {
    for (final item in QuizFocus.values) {
      if (item.name == value) {
        return item;
      }
    }
    return QuizFocus.specs;
  }

  static VarianceDirection _varianceDirectionFromName(String? value) {
    for (final item in VarianceDirection.values) {
      if (item.name == value) {
        return item;
      }
    }
    return VarianceDirection.overpour;
  }

  static RecipeEntityType _recipeEntityTypeFromName(String? value) {
    for (final item in RecipeEntityType.values) {
      if (item.name == value) {
        return item;
      }
    }
    return RecipeEntityType.cocktail;
  }

  static IngredientReferenceType _ingredientReferenceTypeFromName(
    String? value,
  ) {
    for (final item in IngredientReferenceType.values) {
      if (item.name == value) {
        return item;
      }
    }
    return IngredientReferenceType.directIngredient;
  }

  static VarianceSourceType _varianceSourceTypeFromName(String? value) {
    for (final item in VarianceSourceType.values) {
      if (item.name == value) {
        return item;
      }
    }
    return VarianceSourceType.ingredient;
  }

  static UserRole _userRoleFromName(String? value) {
    for (final item in UserRole.values) {
      if (item.name == value) {
        return item;
      }
    }
    return UserRole.bartender;
  }

  static DateTime _dateTimeFromFirestoreValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
