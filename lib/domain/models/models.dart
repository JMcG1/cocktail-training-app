enum UserRole { owner, manager, bartender }

enum QuizKind { stockVariance, practice }

enum QuestionKind {
  ingredientMeasure,
  ingredientChoice,
  cocktailByIngredient,
  garnish,
  glassware,
  method,
  batchAmount,
}

enum VarianceDirection { overpour, underpour }

enum RecipeDraftStatus { pending, approved, deleted }

enum RecipeConfidence { highConfidence, needsReview, possibleOcrIssue }

enum RecipeEntityType { cocktail, batch }

enum IngredientReferenceType { directIngredient, batch }

enum VarianceSourceType { ingredient, batch }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.venueId,
    required this.venueName,
    required this.createdAt,
    required this.active,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String venueId;
  final String venueName;
  final DateTime createdAt;
  final bool active;

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    String? venueId,
    String? venueName,
    DateTime? createdAt,
    bool? active,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      venueId: venueId ?? this.venueId,
      venueName: venueName ?? this.venueName,
      createdAt: createdAt ?? this.createdAt,
      active: active ?? this.active,
    );
  }
}

class VenueProfile {
  const VenueProfile({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.createdAt,
    required this.active,
  });

  final String id;
  final String name;
  final String ownerUid;
  final DateTime createdAt;
  final bool active;
}

class VenueInvite {
  const VenueInvite({
    required this.id,
    required this.venueId,
    required this.role,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    required this.maxUses,
    required this.currentUses,
    required this.disabled,
  });

  final String id;
  final String venueId;
  final UserRole role;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxUses;
  final int currentUses;
  final bool disabled;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isOverused => currentUses >= maxUses;
  bool get isRedeemable => !disabled && !isExpired && !isOverused;

  VenueInvite copyWith({
    String? id,
    String? venueId,
    UserRole? role,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? maxUses,
    int? currentUses,
    bool? disabled,
  }) {
    return VenueInvite(
      id: id ?? this.id,
      venueId: venueId ?? this.venueId,
      role: role ?? this.role,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      maxUses: maxUses ?? this.maxUses,
      currentUses: currentUses ?? this.currentUses,
      disabled: disabled ?? this.disabled,
    );
  }
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.bottleSizeMl,
    required this.bottleCost,
    this.isGarnish = false,
  });

  final String id;
  final String name;
  final double bottleSizeMl;
  final double bottleCost;
  final bool isGarnish;

  double get costPerMl => bottleSizeMl == 0 ? 0 : bottleCost / bottleSizeMl;
  bool get hasCompletePricing =>
      isGarnish || (bottleSizeMl > 0 && bottleCost > 0);

  Ingredient copyWith({
    String? id,
    String? name,
    double? bottleSizeMl,
    double? bottleCost,
    bool? isGarnish,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      bottleSizeMl: bottleSizeMl ?? this.bottleSizeMl,
      bottleCost: bottleCost ?? this.bottleCost,
      isGarnish: isGarnish ?? this.isGarnish,
    );
  }
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientName,
    this.measureMl,
    this.preparationNote,
    this.referenceType = IngredientReferenceType.directIngredient,
    this.linkedBatchId,
  });

  final String ingredientName;
  final double? measureMl;
  final String? preparationNote;
  final IngredientReferenceType referenceType;
  final String? linkedBatchId;

  bool get isBatchReference => referenceType == IngredientReferenceType.batch;

  RecipeIngredient copyWith({
    String? ingredientName,
    double? measureMl,
    String? preparationNote,
    IngredientReferenceType? referenceType,
    String? linkedBatchId,
  }) {
    return RecipeIngredient(
      ingredientName: ingredientName ?? this.ingredientName,
      measureMl: measureMl ?? this.measureMl,
      preparationNote: preparationNote ?? this.preparationNote,
      referenceType: referenceType ?? this.referenceType,
      linkedBatchId: linkedBatchId ?? this.linkedBatchId,
    );
  }
}

class CocktailRecipe {
  const CocktailRecipe({
    required this.id,
    required this.name,
    required this.category,
    required this.glassware,
    required this.garnish,
    required this.method,
    required this.notes,
    required this.ingredients,
    required this.sourceLabel,
    required this.needsReview,
    required this.reviewFlags,
    required this.isApproved,
    required this.wasManuallyReviewed,
    this.imageAssetPath,
    this.missingImage = false,
    this.priceGbp,
  });

  final String id;
  final String name;
  final String category;
  final String glassware;
  final String garnish;
  final String method;
  final String notes;
  final List<RecipeIngredient> ingredients;
  final String sourceLabel;
  final bool needsReview;
  final List<String> reviewFlags;
  final bool isApproved;
  final bool wasManuallyReviewed;
  final String? imageAssetPath;
  final bool missingImage;
  final double? priceGbp;

  bool get hasMeasureData => ingredients.any((item) => item.measureMl != null);

  CocktailRecipe copyWith({
    String? id,
    String? name,
    String? category,
    String? glassware,
    String? garnish,
    String? method,
    String? notes,
    List<RecipeIngredient>? ingredients,
    String? sourceLabel,
    bool? needsReview,
    List<String>? reviewFlags,
    bool? isApproved,
    bool? wasManuallyReviewed,
    String? imageAssetPath,
    bool? missingImage,
    double? priceGbp,
  }) {
    return CocktailRecipe(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      glassware: glassware ?? this.glassware,
      garnish: garnish ?? this.garnish,
      method: method ?? this.method,
      notes: notes ?? this.notes,
      ingredients: ingredients ?? this.ingredients,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      needsReview: needsReview ?? this.needsReview,
      reviewFlags: reviewFlags ?? this.reviewFlags,
      isApproved: isApproved ?? this.isApproved,
      wasManuallyReviewed: wasManuallyReviewed ?? this.wasManuallyReviewed,
      imageAssetPath: imageAssetPath ?? this.imageAssetPath,
      missingImage: missingImage ?? this.missingImage,
      priceGbp: priceGbp ?? this.priceGbp,
    );
  }
}

class BatchRecipe {
  const BatchRecipe({
    required this.id,
    required this.name,
    required this.category,
    required this.notes,
    required this.ingredients,
    required this.totalBatchVolumeMl,
    required this.sourceLabel,
    required this.needsReview,
    required this.reviewFlags,
    required this.isApproved,
    required this.wasManuallyReviewed,
  });

  final String id;
  final String name;
  final String category;
  final String notes;
  final List<RecipeIngredient> ingredients;
  final double? totalBatchVolumeMl;
  final String sourceLabel;
  final bool needsReview;
  final List<String> reviewFlags;
  final bool isApproved;
  final bool wasManuallyReviewed;

  BatchRecipe copyWith({
    String? id,
    String? name,
    String? category,
    String? notes,
    List<RecipeIngredient>? ingredients,
    double? totalBatchVolumeMl,
    String? sourceLabel,
    bool? needsReview,
    List<String>? reviewFlags,
    bool? isApproved,
    bool? wasManuallyReviewed,
  }) {
    return BatchRecipe(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      ingredients: ingredients ?? this.ingredients,
      totalBatchVolumeMl: totalBatchVolumeMl ?? this.totalBatchVolumeMl,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      needsReview: needsReview ?? this.needsReview,
      reviewFlags: reviewFlags ?? this.reviewFlags,
      isApproved: isApproved ?? this.isApproved,
      wasManuallyReviewed: wasManuallyReviewed ?? this.wasManuallyReviewed,
    );
  }
}

class RecipeImportDraft {
  const RecipeImportDraft({
    required this.id,
    required this.sourceLabel,
    required this.pageLabel,
    required this.name,
    required this.category,
    required this.glassware,
    required this.garnish,
    required this.method,
    required this.notes,
    required this.ingredients,
    required this.reviewFlags,
    required this.status,
    required this.wasManuallyReviewed,
    this.entityType = RecipeEntityType.cocktail,
    this.totalBatchVolumeMl,
    this.priceGbp,
  });

  final String id;
  final String sourceLabel;
  final String pageLabel;
  final String name;
  final String category;
  final String glassware;
  final String garnish;
  final String method;
  final String notes;
  final List<RecipeIngredient> ingredients;
  final List<String> reviewFlags;
  final RecipeDraftStatus status;
  final bool wasManuallyReviewed;
  final RecipeEntityType entityType;
  final double? totalBatchVolumeMl;
  final double? priceGbp;

  bool get needsReview => reviewFlags.isNotEmpty;
  bool get isBatch => entityType == RecipeEntityType.batch;

  CocktailRecipe toRecipe() {
    return CocktailRecipe(
      id: id,
      name: name,
      category: category,
      glassware: glassware,
      garnish: garnish,
      method: method,
      notes: notes,
      ingredients: ingredients,
      sourceLabel: sourceLabel,
      needsReview: needsReview,
      reviewFlags: reviewFlags,
      isApproved: status == RecipeDraftStatus.approved,
      wasManuallyReviewed: wasManuallyReviewed,
      priceGbp: priceGbp,
    );
  }

  BatchRecipe toBatchRecipe() {
    return BatchRecipe(
      id: id,
      name: name,
      category: category,
      notes: notes,
      ingredients: ingredients,
      totalBatchVolumeMl: totalBatchVolumeMl,
      sourceLabel: sourceLabel,
      needsReview: needsReview,
      reviewFlags: reviewFlags,
      isApproved: status == RecipeDraftStatus.approved,
      wasManuallyReviewed: wasManuallyReviewed,
    );
  }

  RecipeImportDraft copyWith({
    String? id,
    String? sourceLabel,
    String? pageLabel,
    String? name,
    String? category,
    String? glassware,
    String? garnish,
    String? method,
    String? notes,
    List<RecipeIngredient>? ingredients,
    List<String>? reviewFlags,
    RecipeDraftStatus? status,
    bool? wasManuallyReviewed,
    RecipeEntityType? entityType,
    double? totalBatchVolumeMl,
    double? priceGbp,
  }) {
    return RecipeImportDraft(
      id: id ?? this.id,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      pageLabel: pageLabel ?? this.pageLabel,
      name: name ?? this.name,
      category: category ?? this.category,
      glassware: glassware ?? this.glassware,
      garnish: garnish ?? this.garnish,
      method: method ?? this.method,
      notes: notes ?? this.notes,
      ingredients: ingredients ?? this.ingredients,
      reviewFlags: reviewFlags ?? this.reviewFlags,
      status: status ?? this.status,
      wasManuallyReviewed: wasManuallyReviewed ?? this.wasManuallyReviewed,
      entityType: entityType ?? this.entityType,
      totalBatchVolumeMl: totalBatchVolumeMl ?? this.totalBatchVolumeMl,
      priceGbp: priceGbp ?? this.priceGbp,
    );
  }
}

class RecipeImportResult {
  const RecipeImportResult({
    required this.sourceName,
    required this.drafts,
    required this.warnings,
    required this.requiresOcr,
    required this.rawText,
    required this.pageCount,
  });

  final String sourceName;
  final List<RecipeImportDraft> drafts;
  final List<String> warnings;
  final bool requiresOcr;
  final String rawText;
  final int pageCount;

  bool get hasDrafts => drafts.isNotEmpty;
}

class VerifiedRecipeSyncResult {
  const VerifiedRecipeSyncResult({
    required this.cocktailsAdded,
    required this.cocktailsUpdated,
    required this.cocktailsSkipped,
    required this.batchesAdded,
    required this.batchesUpdated,
    required this.batchesSkipped,
    required this.ingredientsAdded,
    required this.flaggedCocktails,
    required this.flaggedBatches,
    required this.missingImages,
  });

  final int cocktailsAdded;
  final int cocktailsUpdated;
  final int cocktailsSkipped;
  final int batchesAdded;
  final int batchesUpdated;
  final int batchesSkipped;
  final int ingredientsAdded;
  final int flaggedCocktails;
  final int flaggedBatches;
  final int missingImages;

  int get totalCocktailsProcessed =>
      cocktailsAdded + cocktailsUpdated + cocktailsSkipped;

  int get totalBatchesProcessed =>
      batchesAdded + batchesUpdated + batchesSkipped;
}

class StockConcernItem {
  const StockConcernItem({
    required this.ingredientName,
    this.amountShortMl,
    this.estimatedImpact,
    this.notes,
  });

  final String ingredientName;
  final double? amountShortMl;
  final double? estimatedImpact;
  final String? notes;
}

class BartenderSalesEntry {
  const BartenderSalesEntry({
    required this.cocktailId,
    required this.cocktailName,
    required this.quantitySold,
  });

  final String cocktailId;
  final String cocktailName;
  final int quantitySold;
}

class BartenderWeeklySales {
  const BartenderWeeklySales({
    required this.bartenderName,
    required this.entries,
  });

  final String bartenderName;
  final List<BartenderSalesEntry> entries;
}

class WeeklyConcernSession {
  const WeeklyConcernSession({
    required this.id,
    required this.label,
    required this.weekStart,
    required this.concerns,
    required this.targetCocktailIds,
    required this.bartenderSales,
    required this.quizSessionIds,
  });

  final String id;
  final String label;
  final DateTime weekStart;
  final List<StockConcernItem> concerns;
  final List<String> targetCocktailIds;
  final List<BartenderWeeklySales> bartenderSales;
  final List<String> quizSessionIds;

  WeeklyConcernSession copyWith({
    String? id,
    String? label,
    DateTime? weekStart,
    List<StockConcernItem>? concerns,
    List<String>? targetCocktailIds,
    List<BartenderWeeklySales>? bartenderSales,
    List<String>? quizSessionIds,
  }) {
    return WeeklyConcernSession(
      id: id ?? this.id,
      label: label ?? this.label,
      weekStart: weekStart ?? this.weekStart,
      concerns: concerns ?? this.concerns,
      targetCocktailIds: targetCocktailIds ?? this.targetCocktailIds,
      bartenderSales: bartenderSales ?? this.bartenderSales,
      quizSessionIds: quizSessionIds ?? this.quizSessionIds,
    );
  }
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.cocktailId,
    required this.cocktailName,
    required this.kind,
    required this.prompt,
    required this.options,
    required this.correctAnswer,
    this.ingredientName,
    this.correctMeasureMl,
    this.ingredientReferenceType = IngredientReferenceType.directIngredient,
    this.linkedBatchId,
  });

  final String id;
  final String cocktailId;
  final String cocktailName;
  final QuestionKind kind;
  final String prompt;
  final List<String> options;
  final String correctAnswer;
  final String? ingredientName;
  final double? correctMeasureMl;
  final IngredientReferenceType ingredientReferenceType;
  final String? linkedBatchId;
}

class QuizSession {
  const QuizSession({
    required this.id,
    required this.title,
    required this.bartenderName,
    required this.kind,
    required this.isActive,
    required this.createdAt,
    required this.questions,
    this.weekId,
  });

  final String id;
  final String title;
  final String bartenderName;
  final QuizKind kind;
  final bool isActive;
  final DateTime createdAt;
  final List<QuizQuestion> questions;
  final String? weekId;

  QuizSession copyWith({
    String? id,
    String? title,
    String? bartenderName,
    QuizKind? kind,
    bool? isActive,
    DateTime? createdAt,
    List<QuizQuestion>? questions,
    String? weekId,
  }) {
    return QuizSession(
      id: id ?? this.id,
      title: title ?? this.title,
      bartenderName: bartenderName ?? this.bartenderName,
      kind: kind ?? this.kind,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      questions: questions ?? this.questions,
      weekId: weekId ?? this.weekId,
    );
  }
}

class VarianceLine {
  const VarianceLine({
    required this.ingredientName,
    required this.totalMl,
    required this.approximateValue,
    required this.direction,
    this.sourceType = VarianceSourceType.ingredient,
  });

  final String ingredientName;
  final double totalMl;
  final double approximateValue;
  final VarianceDirection direction;
  final VarianceSourceType sourceType;
}

class QuestionResponse {
  const QuestionResponse({
    required this.question,
    required this.selectedAnswer,
    required this.isCorrect,
    required this.quantitySold,
    this.deltaMl,
  });

  final QuizQuestion question;
  final String selectedAnswer;
  final bool isCorrect;
  final int quantitySold;
  final double? deltaMl;
}

class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.sessionId,
    this.userId,
    required this.bartenderName,
    required this.submittedAt,
    required this.scorePercent,
    required this.responses,
    required this.overpourLines,
    required this.underpourLines,
    this.batchOverpourLines = const [],
    this.batchUnderpourLines = const [],
    required this.coachingAreas,
    required this.encouragement,
    this.weekId,
  });

  final String id;
  final String sessionId;
  final String? weekId;
  final String? userId;
  final String bartenderName;
  final DateTime submittedAt;
  final int scorePercent;
  final List<QuestionResponse> responses;
  final List<VarianceLine> overpourLines;
  final List<VarianceLine> underpourLines;
  final List<VarianceLine> batchOverpourLines;
  final List<VarianceLine> batchUnderpourLines;
  final List<String> coachingAreas;
  final String encouragement;
}
