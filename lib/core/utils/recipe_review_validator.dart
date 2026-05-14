import '../../domain/models/models.dart';

class RecipeValidationIssue {
  const RecipeValidationIssue({
    required this.message,
    this.isBlocking = false,
    this.isPossibleOcrIssue = false,
    this.isIncomplete = false,
  });

  final String message;
  final bool isBlocking;
  final bool isPossibleOcrIssue;
  final bool isIncomplete;
}

class RecipeReviewState {
  const RecipeReviewState({required this.confidence, required this.issues});

  final RecipeConfidence confidence;
  final List<RecipeValidationIssue> issues;

  bool get hasBlockingIssues => issues.any((issue) => issue.isBlocking);
  bool get hasPossibleOcrIssue =>
      issues.any((issue) => issue.isPossibleOcrIssue);
  bool get isIncomplete => issues.any((issue) => issue.isIncomplete);
  bool get canApprove => !hasBlockingIssues;
}

class RecipeReviewValidator {
  static RecipeReviewState inspectDraft(RecipeImportDraft draft) {
    return draft.isBatch
        ? _inspectBatchFields(
            name: draft.name,
            ingredients: draft.ingredients,
            totalBatchVolumeMl: draft.totalBatchVolumeMl,
            importedReviewFlags: draft.reviewFlags,
          )
        : _inspectFields(
            name: draft.name,
            garnish: draft.garnish,
            glassware: draft.glassware,
            method: draft.method,
            ingredients: draft.ingredients,
            importedReviewFlags: draft.reviewFlags,
          );
  }

  static RecipeReviewState inspectRecipe(CocktailRecipe recipe) {
    return _inspectFields(
      name: recipe.name,
      garnish: recipe.garnish,
      glassware: recipe.glassware,
      method: recipe.method,
      ingredients: recipe.ingredients,
      importedReviewFlags: recipe.reviewFlags,
    );
  }

  static RecipeReviewState inspectBatch(BatchRecipe recipe) {
    return _inspectBatchFields(
      name: recipe.name,
      ingredients: recipe.ingredients,
      totalBatchVolumeMl: recipe.totalBatchVolumeMl,
      importedReviewFlags: recipe.reviewFlags,
    );
  }

  static RecipeReviewState _inspectFields({
    required String name,
    required String garnish,
    required String glassware,
    required String method,
    required List<RecipeIngredient> ingredients,
    required List<String> importedReviewFlags,
  }) {
    final issues = <RecipeValidationIssue>[];

    for (final flag in importedReviewFlags) {
      final lower = flag.toLowerCase();
      issues.add(
        RecipeValidationIssue(
          message: flag,
          isBlocking:
              (lower.contains('needs review') && lower.contains('name')) ||
              lower.contains('unresolved batch link') ||
              lower.contains('circular batch dependency'),
          isPossibleOcrIssue: lower.contains('possible ocr issue'),
          isIncomplete: lower.contains('missing') || lower.contains('unclear'),
        ),
      );
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message: 'Cocktail name is required before approval.',
          isBlocking: true,
        ),
      );
    }

    if (_looksLikeSuspiciousOcrName(trimmedName)) {
      issues.add(
        const RecipeValidationIssue(
          message:
              'Possible OCR issue in the cocktail name. Please compare it with the source before approval.',
          isPossibleOcrIssue: true,
        ),
      );
    }

    final namedIngredients = ingredients
        .map(
          (ingredient) => ingredient.copyWith(
            ingredientName: ingredient.ingredientName.trim(),
          ),
        )
        .where((ingredient) => ingredient.ingredientName.isNotEmpty)
        .toList();

    if (namedIngredients.isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message: 'At least one ingredient is required before approval.',
          isBlocking: true,
        ),
      );
    }

    final seenNames = <String>{};
    for (final ingredient in namedIngredients) {
      final normalizedName = ingredient.ingredientName.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Duplicate ingredient listed: ${ingredient.ingredientName}.',
            isBlocking: true,
          ),
        );
      }

      final measure = ingredient.measureMl;
      if (measure == null) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Measure missing or unclear for ${ingredient.ingredientName}.',
            isIncomplete: true,
          ),
        );
        continue;
      }

      if (measure <= 0) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Measure for ${ingredient.ingredientName} must be greater than 0ml.',
            isBlocking: true,
          ),
        );
      } else if (measure < 5 || measure > 250) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Measure for ${ingredient.ingredientName} looks unusual at ${measure.toStringAsFixed(measure.truncateToDouble() == measure ? 0 : 1)}ml. Please review it.',
            isIncomplete: true,
          ),
        );
      }
    }

    if (glassware.trim().isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message:
              'Glassware is blank. You can still save it, but it will stay marked as incomplete.',
          isIncomplete: true,
        ),
      );
    }
    if (garnish.trim().isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message:
              'Garnish is blank. You can still save it, but it will stay marked as incomplete.',
          isIncomplete: true,
        ),
      );
    }
    if (method.trim().isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message:
              'Method is blank. You can still save it, but it will stay marked as incomplete.',
          isIncomplete: true,
        ),
      );
    }

    final confidence = issues.any((issue) => issue.isPossibleOcrIssue)
        ? RecipeConfidence.possibleOcrIssue
        : issues.any((issue) => issue.isBlocking || issue.isIncomplete)
        ? RecipeConfidence.needsReview
        : RecipeConfidence.highConfidence;

    return RecipeReviewState(
      confidence: confidence,
      issues: _dedupeIssues(issues),
    );
  }

  static RecipeReviewState _inspectBatchFields({
    required String name,
    required List<RecipeIngredient> ingredients,
    required double? totalBatchVolumeMl,
    required List<String> importedReviewFlags,
  }) {
    final issues = <RecipeValidationIssue>[];

    for (final flag in importedReviewFlags) {
      final lower = flag.toLowerCase();
      issues.add(
        RecipeValidationIssue(
          message: flag,
          isBlocking:
              lower.contains('unresolved') ||
              lower.contains('circular') ||
              lower.contains('required') ||
              lower.contains('must be greater than 0'),
          isPossibleOcrIssue:
              lower.contains('possible ocr issue') ||
              lower.contains('suspicious'),
          isIncomplete:
              lower.contains('missing') ||
              lower.contains('unclear') ||
              lower.contains('review'),
        ),
      );
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message: 'Batch name is required before approval.',
          isBlocking: true,
        ),
      );
    }

    final namedIngredients = ingredients
        .map(
          (ingredient) => ingredient.copyWith(
            ingredientName: ingredient.ingredientName.trim(),
          ),
        )
        .where((ingredient) => ingredient.ingredientName.isNotEmpty)
        .toList();
    if (namedIngredients.isEmpty) {
      issues.add(
        const RecipeValidationIssue(
          message: 'At least one batch ingredient is required before approval.',
          isBlocking: true,
        ),
      );
    }
    if ((totalBatchVolumeMl ?? 0) <= 0) {
      issues.add(
        const RecipeValidationIssue(
          message: 'Batch total volume is required before approval.',
          isBlocking: true,
        ),
      );
    }

    final seenNames = <String>{};
    for (final ingredient in namedIngredients) {
      final normalizedName = ingredient.ingredientName.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Duplicate batch ingredient listed: ${ingredient.ingredientName}.',
            isBlocking: true,
          ),
        );
      }
      final measure = ingredient.measureMl;
      if (measure == null || measure <= 0) {
        issues.add(
          RecipeValidationIssue(
            message:
                'Batch ingredient ${ingredient.ingredientName} needs a clear ml amount.',
            isBlocking: true,
          ),
        );
      }
    }

    final confidence = issues.any((issue) => issue.isPossibleOcrIssue)
        ? RecipeConfidence.possibleOcrIssue
        : issues.any((issue) => issue.isBlocking || issue.isIncomplete)
        ? RecipeConfidence.needsReview
        : RecipeConfidence.highConfidence;

    return RecipeReviewState(
      confidence: confidence,
      issues: _dedupeIssues(issues),
    );
  }

  static bool _looksLikeSuspiciousOcrName(String name) {
    final normalized = name.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'NEEDS REVIEW') {
      return true;
    }
    const suspiciousTokens = ['SRAMBLE', 'APERNOL'];
    if (suspiciousTokens.any(normalized.contains)) {
      return true;
    }
    return false;
  }

  static List<RecipeValidationIssue> _dedupeIssues(
    List<RecipeValidationIssue> issues,
  ) {
    final seen = <String>{};
    final deduped = <RecipeValidationIssue>[];
    for (final issue in issues) {
      final key =
          '${issue.message}|${issue.isBlocking}|${issue.isPossibleOcrIssue}|${issue.isIncomplete}';
      if (seen.add(key)) {
        deduped.add(issue);
      }
    }
    return deduped;
  }
}
