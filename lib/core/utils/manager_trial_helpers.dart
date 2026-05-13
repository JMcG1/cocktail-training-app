import '../../domain/models/models.dart';

class RecipeDraftCounts {
  const RecipeDraftCounts({
    required this.approved,
    required this.needsReview,
    required this.possibleOcrIssue,
    required this.deleted,
  });

  final int approved;
  final int needsReview;
  final int possibleOcrIssue;
  final int deleted;
}

class SalesValidationResult {
  const SalesValidationResult({
    required this.isValid,
    this.message,
  });

  final bool isValid;
  final String? message;
}

class StockWorkflowProgress {
  const StockWorkflowProgress({
    required this.concernsSelected,
    required this.cocktailsReviewed,
    required this.salesEntered,
    required this.quizLaunched,
    required this.resultsAvailable,
  });

  final bool concernsSelected;
  final bool cocktailsReviewed;
  final bool salesEntered;
  final bool quizLaunched;
  final bool resultsAvailable;
}

class ManagerTrialHelpers {
  const ManagerTrialHelpers._();

  static List<RecipeImportDraft> filterDrafts({
    required List<RecipeImportDraft> drafts,
    String query = '',
    RecipeConfidence? confidence,
    String? category,
    bool includeDeleted = false,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return drafts.where((draft) {
      if (!includeDeleted && draft.status == RecipeDraftStatus.deleted) {
        return false;
      }
      final review = _confidenceForDraft(draft);
      final matchesConfidence = confidence == null || review == confidence;
      final matchesCategory = category == null ||
          category == 'All categories' ||
          draft.category.trim() == category;
      final matchesQuery = normalizedQuery.isEmpty ||
          draft.name.toLowerCase().contains(normalizedQuery) ||
          draft.category.toLowerCase().contains(normalizedQuery);
      return matchesConfidence && matchesCategory && matchesQuery;
    }).toList();
  }

  static RecipeDraftCounts countDrafts(List<RecipeImportDraft> drafts) {
    var approved = 0;
    var needsReview = 0;
    var possibleOcrIssue = 0;
    var deleted = 0;
    for (final draft in drafts) {
      if (draft.status == RecipeDraftStatus.deleted) {
        deleted += 1;
        continue;
      }
      if (draft.status == RecipeDraftStatus.approved) {
        approved += 1;
      }
      final confidence = _confidenceForDraft(draft);
      if (confidence == RecipeConfidence.possibleOcrIssue) {
        possibleOcrIssue += 1;
      } else if (confidence == RecipeConfidence.needsReview) {
        needsReview += 1;
      }
    }
    return RecipeDraftCounts(
      approved: approved,
      needsReview: needsReview,
      possibleOcrIssue: possibleOcrIssue,
      deleted: deleted,
    );
  }

  static SalesValidationResult validateBartenderSales({
    required WeeklyConcernSession session,
    required String bartenderName,
    required Map<String, String> rawQuantitiesByCocktailId,
  }) {
    final trimmedName = bartenderName.trim();
    if (trimmedName.isEmpty) {
      return const SalesValidationResult(
        isValid: false,
        message: 'Enter the bartender name before saving sales.',
      );
    }

    final duplicate = session.bartenderSales.any(
      (sales) => sales.bartenderName.toLowerCase() == trimmedName.toLowerCase(),
    );
    if (duplicate) {
      return const SalesValidationResult(
        isValid: false,
        message: 'That bartender already has sales saved for this session. Update the existing entry instead of duplicating the name.',
      );
    }

    for (final entry in rawQuantitiesByCocktailId.entries) {
      final raw = entry.value.trim();
      if (raw.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 0) {
        return const SalesValidationResult(
          isValid: false,
          message: 'Sales quantities must be whole numbers and cannot be negative.',
        );
      }
    }

    return const SalesValidationResult(isValid: true);
  }

  static StockWorkflowProgress buildStockWorkflowProgress({
    WeeklyConcernSession? session,
    required List<QuizSession> quizSessions,
    required List<QuizAttempt> quizAttempts,
  }) {
    if (session == null) {
      return const StockWorkflowProgress(
        concernsSelected: false,
        cocktailsReviewed: false,
        salesEntered: false,
        quizLaunched: false,
        resultsAvailable: false,
      );
    }
    final concernsSelected = session.concerns.isNotEmpty;
    final cocktailsReviewed = session.targetCocktailIds.isNotEmpty;
    final salesEntered = session.bartenderSales.any((sales) => sales.entries.isNotEmpty);
    final quizLaunched = quizSessions.any((quiz) => quiz.weekId == session.id);
    final resultsAvailable = quizAttempts.any((attempt) => attempt.weekId == session.id);
    return StockWorkflowProgress(
      concernsSelected: concernsSelected,
      cocktailsReviewed: cocktailsReviewed,
      salesEntered: salesEntered,
      quizLaunched: quizLaunched,
      resultsAvailable: resultsAvailable,
    );
  }

  static bool wordingIsSupportive(String text) {
    final lower = text.toLowerCase();
    return !lower.contains('you lost') &&
        !lower.contains('caused') &&
        !lower.contains('responsible');
  }

  static RecipeConfidence _confidenceForDraft(RecipeImportDraft draft) {
    final flags = draft.reviewFlags.join(' ').toLowerCase();
    if (flags.contains('possible ocr issue')) {
      return RecipeConfidence.possibleOcrIssue;
    }
    if (draft.reviewFlags.isNotEmpty) {
      return RecipeConfidence.needsReview;
    }
    return RecipeConfidence.highConfidence;
  }
}
