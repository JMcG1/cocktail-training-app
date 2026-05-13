import '../../domain/models/models.dart';

class BatchResolutionIssue {
  const BatchResolutionIssue({
    required this.recipeId,
    required this.recipeName,
    required this.message,
    required this.isBlocking,
  });

  final String recipeId;
  final String recipeName;
  final String message;
  final bool isBlocking;
}

class BatchCostSummary {
  const BatchCostSummary({
    required this.totalCost,
    required this.costPerMl,
    required this.missingIngredientCosts,
    required this.missingBatchLinks,
    required this.hasCircularDependency,
  });

  final double totalCost;
  final double costPerMl;
  final List<String> missingIngredientCosts;
  final List<String> missingBatchLinks;
  final bool hasCircularDependency;
}

class BatchUsageComponent {
  const BatchUsageComponent({
    required this.ingredientName,
    required this.totalMl,
    required this.approximateValue,
  });

  final String ingredientName;
  final double totalMl;
  final double approximateValue;
}

class BatchDecompositionResult {
  const BatchDecompositionResult({
    required this.components,
    required this.missingBatchLinks,
    required this.hasCircularDependency,
  });

  final List<BatchUsageComponent> components;
  final List<String> missingBatchLinks;
  final bool hasCircularDependency;
}

class BatchGraphResolver {
  const BatchGraphResolver._();

  static String normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeBatchReference(String value) {
    var normalized = normalizeKey(value);
    normalized = normalized.replaceAll(RegExp(r'\bbatch\b'), ' ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool looksLikeBatchReference(String value) {
    final normalized = normalizeKey(value);
    return normalized.contains(' batch') || normalized.endsWith('batch');
  }

  static Map<String, BatchRecipe> buildBatchIndex(Iterable<BatchRecipe> batches) {
    final index = <String, BatchRecipe>{};
    for (final batch in batches) {
      index[normalizeKey(batch.id)] = batch;
      index[normalizeKey(batch.name)] = batch;
      index[normalizeBatchReference(batch.id)] = batch;
      index[normalizeBatchReference(batch.name)] = batch;
    }
    return index;
  }

  static RecipeIngredient linkIngredientToBatch({
    required RecipeIngredient ingredient,
    required Map<String, BatchRecipe> batchIndex,
  }) {
    final linkedBatch = batchIndex[normalizeKey(ingredient.ingredientName)] ??
        batchIndex[normalizeBatchReference(ingredient.ingredientName)];
    if (linkedBatch == null) {
      return ingredient.copyWith(
        referenceType: looksLikeBatchReference(ingredient.ingredientName)
            ? IngredientReferenceType.batch
            : IngredientReferenceType.directIngredient,
        linkedBatchId: null,
      );
    }
    return ingredient.copyWith(
      referenceType: IngredientReferenceType.batch,
      linkedBatchId: linkedBatch.id,
    );
  }

  static List<RecipeImportDraft> linkDrafts(List<RecipeImportDraft> drafts) {
    final batches = drafts.where((draft) => draft.isBatch).map((draft) => draft.toBatchRecipe());
    final batchIndex = buildBatchIndex(batches);
    final linked = drafts.map((draft) {
      final linkedIngredients = draft.ingredients
          .map((ingredient) => linkIngredientToBatch(ingredient: ingredient, batchIndex: batchIndex))
          .toList();
      final reviewFlags = <String>{...draft.reviewFlags};
      if (!draft.isBatch) {
        for (final ingredient in linkedIngredients.where((item) => item.isBatchReference)) {
          if ((ingredient.linkedBatchId ?? '').isEmpty) {
            reviewFlags.add(
              'Unresolved batch link for ${ingredient.ingredientName}. Match it to an approved batch before approval.',
            );
          }
        }
      }
      return draft.copyWith(
        ingredients: linkedIngredients,
        reviewFlags: reviewFlags.toList(),
      );
    }).toList();

    final batchRecipes = linked.where((draft) => draft.isBatch).map((draft) => draft.toBatchRecipe()).toList();
    final issues = validateBatches(batchRecipes);
    return linked.map((draft) {
      final flags = <String>{...draft.reviewFlags};
      for (final issue in issues.where((issue) => issue.recipeId == draft.id)) {
        flags.add(issue.message);
      }
      return draft.copyWith(reviewFlags: flags.toList());
    }).toList();
  }

  static List<CocktailRecipe> linkCocktailsToBatches({
    required List<CocktailRecipe> cocktails,
    required List<BatchRecipe> batches,
  }) {
    final batchIndex = buildBatchIndex(batches);
    return cocktails.map((recipe) {
      final linkedIngredients = recipe.ingredients
          .map((ingredient) => linkIngredientToBatch(ingredient: ingredient, batchIndex: batchIndex))
          .toList();
      final reviewFlags = <String>{...recipe.reviewFlags};
      for (final ingredient in linkedIngredients.where((item) => item.isBatchReference)) {
        if ((ingredient.linkedBatchId ?? '').isEmpty) {
          reviewFlags.add(
            'Unresolved batch link for ${ingredient.ingredientName}. Match it to an approved batch before approval.',
          );
        }
      }
      return recipe.copyWith(
        ingredients: linkedIngredients,
        reviewFlags: reviewFlags.toList(),
        needsReview: reviewFlags.isNotEmpty,
      );
    }).toList();
  }

  static List<BatchResolutionIssue> validateBatches(List<BatchRecipe> batches) {
    final issues = <BatchResolutionIssue>[];
    final batchById = {for (final batch in batches) batch.id: batch};
    final seenCircular = <String>{};

    for (final batch in batches) {
      if (batch.ingredients.isEmpty) {
        issues.add(
          BatchResolutionIssue(
            recipeId: batch.id,
            recipeName: batch.name,
            message: 'Batch ingredients are required before approval.',
            isBlocking: true,
          ),
        );
      }
      if ((batch.totalBatchVolumeMl ?? 0) <= 0) {
        issues.add(
          BatchResolutionIssue(
            recipeId: batch.id,
            recipeName: batch.name,
            message: 'Batch total volume is missing or must be greater than 0ml.',
            isBlocking: true,
          ),
        );
      }

      final namedIngredients = batch.ingredients
          .map((ingredient) => ingredient.ingredientName.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      final duplicates = <String>{};
      final seen = <String>{};
      for (final name in namedIngredients) {
        final key = normalizeKey(name);
        if (!seen.add(key)) {
          duplicates.add(name);
        }
      }
      for (final name in duplicates) {
        issues.add(
          BatchResolutionIssue(
            recipeId: batch.id,
            recipeName: batch.name,
            message: 'Duplicate batch ingredient listed: $name.',
            isBlocking: true,
          ),
        );
      }

      for (final ingredient in batch.ingredients) {
        if ((ingredient.measureMl ?? 0) <= 0) {
          issues.add(
            BatchResolutionIssue(
              recipeId: batch.id,
              recipeName: batch.name,
              message: 'Batch ingredient ${ingredient.ingredientName} needs a clear ml amount.',
              isBlocking: true,
            ),
          );
        }
        if (ingredient.isBatchReference && (ingredient.linkedBatchId ?? '').isEmpty) {
          issues.add(
            BatchResolutionIssue(
              recipeId: batch.id,
              recipeName: batch.name,
              message: 'Unresolved nested batch link for ${ingredient.ingredientName}.',
              isBlocking: true,
            ),
          );
        }
      }

      if (_containsCircularDependency(batch.id, batchById, <String>{}, seenCircular)) {
        issues.add(
          BatchResolutionIssue(
            recipeId: batch.id,
            recipeName: batch.name,
            message: 'Circular batch dependency detected. Remove the circular link before approval.',
            isBlocking: true,
          ),
        );
      }
    }

    return issues;
  }

  static bool _containsCircularDependency(
    String batchId,
    Map<String, BatchRecipe> batchById,
    Set<String> stack,
    Set<String> memo,
  ) {
    if (stack.contains(batchId)) {
      return true;
    }
    if (memo.contains(batchId)) {
      return false;
    }
    final batch = batchById[batchId];
    if (batch == null) {
      return false;
    }
    stack.add(batchId);
    for (final ingredient in batch.ingredients.where((item) => item.isBatchReference)) {
      final linkedId = ingredient.linkedBatchId;
      if (linkedId == null || linkedId.isEmpty) {
        continue;
      }
      if (_containsCircularDependency(linkedId, batchById, stack, memo)) {
        return true;
      }
    }
    stack.remove(batchId);
    memo.add(batchId);
    return false;
  }

  static BatchCostSummary summarizeBatchCost({
    required BatchRecipe batch,
    required Map<String, Ingredient> ingredientsByName,
    required List<BatchRecipe> batches,
  }) {
    final decomposition = decomposeBatchVolume(
      batchId: batch.id,
      volumeMl: batch.totalBatchVolumeMl ?? 0,
      batches: batches,
      ingredientsByName: ingredientsByName,
    );
    final totalCost = decomposition.components.fold<double>(
      0,
      (sum, item) => sum + item.approximateValue,
    );
    return BatchCostSummary(
      totalCost: totalCost,
      costPerMl: (batch.totalBatchVolumeMl ?? 0) <= 0 ? 0 : totalCost / batch.totalBatchVolumeMl!,
      missingIngredientCosts: decomposition.components
          .where((component) => component.approximateValue == 0 && !ingredientsByName.containsKey(normalizeKey(component.ingredientName)))
          .map((component) => component.ingredientName)
          .toSet()
          .toList(),
      missingBatchLinks: decomposition.missingBatchLinks,
      hasCircularDependency: decomposition.hasCircularDependency,
    );
  }

  static BatchDecompositionResult decomposeCocktailIngredient(
    RecipeIngredient ingredient, {
    required List<BatchRecipe> batches,
    required Map<String, Ingredient> ingredientsByName,
  }) {
    if (!ingredient.isBatchReference || ingredient.linkedBatchId == null || ingredient.linkedBatchId!.isEmpty) {
      final ml = ingredient.measureMl ?? 0;
      final cost = (ingredientsByName[normalizeKey(ingredient.ingredientName)]?.costPerMl ?? 0) * ml;
      return BatchDecompositionResult(
        components: [
          BatchUsageComponent(
            ingredientName: ingredient.ingredientName,
            totalMl: ml,
            approximateValue: cost,
          ),
        ],
        missingBatchLinks: const [],
        hasCircularDependency: false,
      );
    }
    return decomposeBatchVolume(
      batchId: ingredient.linkedBatchId!,
      volumeMl: ingredient.measureMl ?? 0,
      batches: batches,
      ingredientsByName: ingredientsByName,
    );
  }

  static BatchDecompositionResult decomposeBatchVolume({
    required String batchId,
    required double volumeMl,
    required List<BatchRecipe> batches,
    required Map<String, Ingredient> ingredientsByName,
  }) {
    final batchById = {for (final batch in batches) batch.id: batch};
    final buckets = <String, BatchUsageComponent>{};
    final missingBatchLinks = <String>{};
    final hasCircularDependency = _expandBatch(
      batchId: batchId,
      requestedMl: volumeMl,
      batchById: batchById,
      ingredientsByName: ingredientsByName,
      buckets: buckets,
      missingBatchLinks: missingBatchLinks,
      stack: <String>{},
    );
    return BatchDecompositionResult(
      components: buckets.values.toList()..sort((a, b) => b.totalMl.compareTo(a.totalMl)),
      missingBatchLinks: missingBatchLinks.toList()..sort(),
      hasCircularDependency: hasCircularDependency,
    );
  }

  static bool _expandBatch({
    required String batchId,
    required double requestedMl,
    required Map<String, BatchRecipe> batchById,
    required Map<String, Ingredient> ingredientsByName,
    required Map<String, BatchUsageComponent> buckets,
    required Set<String> missingBatchLinks,
    required Set<String> stack,
  }) {
    if (requestedMl == 0) {
      return false;
    }
    if (stack.contains(batchId)) {
      return true;
    }
    final batch = batchById[batchId];
    if (batch == null || (batch.totalBatchVolumeMl ?? 0) <= 0) {
      missingBatchLinks.add(batchId);
      return false;
    }

    stack.add(batchId);
    var hasCircularDependency = false;
    final totalVolume = batch.totalBatchVolumeMl!;
    for (final ingredient in batch.ingredients) {
      final measureMl = ingredient.measureMl;
      if (measureMl == null || measureMl <= 0) {
        continue;
      }
      final proportionalMl = requestedMl * (measureMl / totalVolume);
      if (ingredient.isBatchReference && (ingredient.linkedBatchId ?? '').isNotEmpty) {
        hasCircularDependency = _expandBatch(
              batchId: ingredient.linkedBatchId!,
              requestedMl: proportionalMl,
              batchById: batchById,
              ingredientsByName: ingredientsByName,
              buckets: buckets,
              missingBatchLinks: missingBatchLinks,
              stack: stack,
            ) ||
            hasCircularDependency;
        continue;
      }
      final key = normalizeKey(ingredient.ingredientName);
      final ingredientCost = ingredientsByName[key]?.costPerMl ?? 0;
      final component = buckets[key];
      final next = BatchUsageComponent(
        ingredientName: ingredient.ingredientName,
        totalMl: (component?.totalMl ?? 0) + proportionalMl,
        approximateValue: (component?.approximateValue ?? 0) + (ingredientCost * proportionalMl),
      );
      buckets[key] = next;
    }
    stack.remove(batchId);
    return hasCircularDependency;
  }

  static bool cocktailUsesConcernIngredient({
    required CocktailRecipe cocktail,
    required Set<String> concernNames,
    required List<BatchRecipe> batches,
    required Map<String, Ingredient> ingredientsByName,
  }) {
    for (final ingredient in cocktail.ingredients) {
      if (!ingredient.isBatchReference) {
        if (concernNames.contains(normalizeKey(ingredient.ingredientName))) {
          return true;
        }
        continue;
      }
      final decomposition = decomposeCocktailIngredient(
        ingredient,
        batches: batches,
        ingredientsByName: ingredientsByName,
      );
      if (decomposition.components.any((item) => concernNames.contains(normalizeKey(item.ingredientName)))) {
        return true;
      }
    }
    return false;
  }
}
