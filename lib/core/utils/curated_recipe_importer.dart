import 'dart:convert';

import 'approved_cocktail_prices.dart';
import '../../domain/models/models.dart';
import 'batch_recipe_graph.dart';

enum CuratedImportConflictMode { skipExisting, updateExisting, importOnlyNew }

class CuratedImportPlan {
  const CuratedImportPlan({
    required this.importResult,
    required this.conflictMode,
    required this.totalRecipes,
    required this.newRecipes,
    required this.existingRecipes,
    required this.skippedRecipes,
  });

  final RecipeImportResult importResult;
  final CuratedImportConflictMode conflictMode;
  final int totalRecipes;
  final int newRecipes;
  final int existingRecipes;
  final int skippedRecipes;

  bool get hasExistingRecipes => existingRecipes > 0;
}

class VerifiedRecipeCatalog {
  const VerifiedRecipeCatalog({required this.recipes, required this.batches});

  final List<CocktailRecipe> recipes;
  final List<BatchRecipe> batches;

  int get missingImageCount =>
      recipes.where((recipe) => recipe.missingImage).length;

  int get flaggedRecipeCount =>
      recipes.where((recipe) => recipe.needsReview).length;

  int get flaggedBatchCount =>
      batches.where((batch) => batch.needsReview).length;
}

class CuratedRecipeImporter {
  static const sourceLabel = 'Curated cocktail specs dataset';
  static const assetPath = cocktailAssetPath;
  static const cocktailAssetPath = 'assets/data/cocktails.json';
  static const batchAssetPath = 'assets/data/batches.json';

  const CuratedRecipeImporter();

  CuratedImportPlan buildPlan({
    required String cocktailJsonText,
    required String batchJsonText,
    required List<CocktailRecipe> existingRecipes,
    required List<BatchRecipe> existingBatches,
    required CuratedImportConflictMode conflictMode,
  }) {
    final decodedCocktails = _decodeList(cocktailJsonText, cocktailAssetPath);
    final decodedBatches = _decodeList(batchJsonText, batchAssetPath);

    final existingCocktailsByName = <String, CocktailRecipe>{
      for (final recipe in existingRecipes) ...{
        for (final key in _cocktailLookupKeys(recipe.name)) key: recipe,
      },
    };
    final existingBatchesByName = <String, BatchRecipe>{
      for (final batch in existingBatches) _normalizeName(batch.name): batch,
      for (final batch in existingBatches) _normalizeName(batch.id): batch,
    };

    final batchBlueprints = decodedBatches.map(_parseBatchBlueprint).toList();
    final cocktailBatchIndex = <String, _BatchBlueprint>{
      for (final batch in batchBlueprints) ...{
        _normalizeName(batch.name): batch,
        _normalizeName(batch.id): batch,
        for (final alias in batch.aliases) _normalizeName(alias): batch,
      },
    };

    final drafts = <RecipeImportDraft>[];
    var totalRecipes = 0;
    var newRecipes = 0;
    var existingCount = 0;
    var skippedRecipes = 0;

    for (final batch in batchBlueprints) {
      final existing =
          existingBatchesByName[_normalizeName(batch.name)] ??
          existingBatchesByName[_normalizeName(batch.id)];
      final isExisting = existing != null;
      if (isExisting) {
        existingCount += 1;
      } else {
        newRecipes += 1;
      }
      if (isExisting &&
          conflictMode == CuratedImportConflictMode.importOnlyNew) {
        skippedRecipes += 1;
        continue;
      }
      totalRecipes += 1;
      final reviewFlags = <String>[...batch.reviewFlags];
      if (isExisting) {
        reviewFlags.add(_existingConflictMessage(conflictMode));
      }
      drafts.add(
        RecipeImportDraft(
          id:
              isExisting &&
                  conflictMode == CuratedImportConflictMode.updateExisting
              ? existing.id
              : batch.id,
          sourceLabel: sourceLabel,
          pageLabel: batch.category.isEmpty
              ? 'Curated dataset'
              : batch.category,
          name: batch.name,
          category: batch.category,
          glassware: '',
          garnish: '',
          method: '',
          notes: batch.notes,
          ingredients: batch.ingredients,
          reviewFlags: reviewFlags,
          status: RecipeDraftStatus.pending,
          wasManuallyReviewed: false,
          entityType: RecipeEntityType.batch,
          totalBatchVolumeMl: batch.totalBatchVolumeMl,
        ),
      );
    }

    final batchDrafts = drafts.where((draft) => draft.isBatch).toList();
    for (final entry in decodedCocktails.whereType<Map>()) {
      final data = Map<String, dynamic>.from(entry);
      final name = _cleanText(data['name'] as String? ?? '');
      if (name.isEmpty) {
        continue;
      }
      totalRecipes += 1;
      final existing = _findExistingCocktail(
        lookup: existingCocktailsByName,
        name: name,
      );
      final isExisting = existing != null;
      if (isExisting) {
        existingCount += 1;
      } else {
        newRecipes += 1;
      }
      if (isExisting &&
          conflictMode == CuratedImportConflictMode.importOnlyNew) {
        skippedRecipes += 1;
        continue;
      }

      final originalNotes = _cleanText(data['notes'] as String? ?? '');
      final ice = _cleanText(data['ice'] as String? ?? '');
      final notes = _composeNotes(originalNotes: originalNotes, ice: ice);
      final category = _cleanText(data['category'] as String? ?? '');
      final garnish = _cleanText(data['garnish'] as String? ?? '');
      final glass = _cleanText(data['glass'] as String? ?? '');
      final method = _cleanText(data['method'] as String? ?? '');
      final reviewFlags = <String>[];

      if (isExisting) {
        reviewFlags.add(_existingConflictMessage(conflictMode));
      }
      if (garnish.isEmpty) {
        reviewFlags.add(
          'Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.',
        );
      }

      final ingredients = _parseCocktailIngredients(
        data['ingredients'],
        batchIndex: cocktailBatchIndex,
      );
      for (final ingredient in ingredients.where(
        (item) => item.isBatchReference,
      )) {
        if ((ingredient.linkedBatchId ?? '').isEmpty) {
          reviewFlags.add(
            'Unresolved batch link for ${ingredient.ingredientName}. Match it to an approved batch before approval.',
          );
        }
      }

      final id =
          isExisting && conflictMode == CuratedImportConflictMode.updateExisting
          ? existing.id
          : _cleanText(data['id'] as String? ?? _slugify(name));
      drafts.add(
        RecipeImportDraft(
          id: id,
          sourceLabel: sourceLabel,
          pageLabel: category.isEmpty ? 'Curated dataset' : category,
          name: name,
          category: category,
          glassware: glass,
          garnish: garnish,
          method: method,
          notes: notes,
          ingredients: ingredients,
          reviewFlags: reviewFlags,
          status: RecipeDraftStatus.pending,
          wasManuallyReviewed: false,
          priceGbp:
              (data['priceGbp'] as num?)?.toDouble() ??
              approvedCocktailPriceGbpForName(name),
        ),
      );
    }

    final linkedDrafts = BatchGraphResolver.linkDrafts([
      ...batchDrafts,
      ...drafts.where((draft) => !draft.isBatch),
    ]);

    final warnings = <String>[
      'Curated specs are loaded from $cocktailAssetPath and $batchAssetPath and still follow the no-invention rule.',
      if (existingCount > 0)
        switch (conflictMode) {
          CuratedImportConflictMode.skipExisting =>
            '$existingCount imported item${existingCount == 1 ? '' : 's'} already exist in this venue and will be skipped when you confirm the import.',
          CuratedImportConflictMode.updateExisting =>
            '$existingCount imported item${existingCount == 1 ? '' : 's'} already exist in this venue and will update in place when approved.',
          CuratedImportConflictMode.importOnlyNew =>
            '$existingCount existing item match${existingCount == 1 ? '' : 'es'} were left out so you can review only new imports.',
        },
    ];

    return CuratedImportPlan(
      importResult: RecipeImportResult(
        sourceName: sourceLabel,
        drafts: linkedDrafts,
        warnings: warnings,
        requiresOcr: false,
        rawText: '$batchJsonText\n$cocktailJsonText',
        pageCount: decodedCocktails.length + decodedBatches.length,
      ),
      conflictMode: conflictMode,
      totalRecipes: totalRecipes,
      newRecipes: newRecipes,
      existingRecipes: existingCount,
      skippedRecipes: skippedRecipes,
    );
  }

  VerifiedRecipeCatalog buildVerifiedCatalog({
    required String cocktailJsonText,
    required String batchJsonText,
  }) {
    final decodedCocktails = _decodeList(cocktailJsonText, cocktailAssetPath);
    final decodedBatches = _decodeList(batchJsonText, batchAssetPath);

    final batchBlueprints = decodedBatches.map(_parseBatchBlueprint).toList();
    final batchIndex = <String, _BatchBlueprint>{
      for (final batch in batchBlueprints) ...{
        _normalizeName(batch.name): batch,
        _normalizeName(batch.id): batch,
        for (final alias in batch.aliases) _normalizeName(alias): batch,
      },
    };

    final rawBatches = batchBlueprints
        .map(
          (batch) => BatchRecipe(
            id: batch.id,
            name: batch.name,
            category: batch.category,
            notes: batch.notes,
            ingredients: batch.ingredients,
            totalBatchVolumeMl: batch.totalBatchVolumeMl,
            sourceLabel: sourceLabel,
            needsReview: batch.reviewFlags.isNotEmpty,
            reviewFlags: List.unmodifiable(batch.reviewFlags),
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        )
        .toList();

    final linkedBatches = rawBatches
        .map((batch) => _linkBatchRecipe(batch, rawBatches))
        .toList();

    final rawRecipes = decodedCocktails
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((data) => _parseVerifiedRecipe(data, batchIndex: batchIndex))
        .whereType<CocktailRecipe>()
        .toList();

    final linkedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: rawRecipes,
      batches: linkedBatches,
    );

    return VerifiedRecipeCatalog(
      recipes: linkedRecipes,
      batches: linkedBatches,
    );
  }

  List<dynamic> _decodeList(String jsonText, String assetPath) {
    final decoded = json.decode(jsonText);
    if (decoded is! List) {
      throw FormatException(
        'Curated dataset at $assetPath must be a top-level JSON list.',
      );
    }
    return decoded;
  }

  _BatchBlueprint _parseBatchBlueprint(dynamic entry) {
    if (entry is! Map) {
      throw const FormatException(
        'Curated batch dataset entries must be JSON objects.',
      );
    }
    final data = Map<String, dynamic>.from(entry);
    return _BatchBlueprint(
      id: _cleanText(data['id'] as String? ?? ''),
      name: _cleanText(data['name'] as String? ?? ''),
      category: _cleanText(data['category'] as String? ?? 'Batch Recipes'),
      notes: _cleanText(data['notes'] as String? ?? ''),
      totalBatchVolumeMl:
          _parseMlAmount(_cleanText(data['totalVolume'] as String? ?? '')) ??
          (data['totalVolumeMl'] as num?)?.toDouble(),
      ingredients: _parseBatchIngredients(data['ingredients']),
      aliases: (data['aliases'] as List<dynamic>? ?? const []).cast<String>(),
      reviewFlags: (data['reviewFlags'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }

  CocktailRecipe? _parseVerifiedRecipe(
    Map<String, dynamic> data, {
    required Map<String, _BatchBlueprint> batchIndex,
  }) {
    final name = _cleanText(data['name'] as String? ?? '');
    if (name.isEmpty) {
      return null;
    }
    final originalNotes = _cleanText(data['notes'] as String? ?? '');
    final ice = _cleanText(data['ice'] as String? ?? '');
    final notes = _composeNotes(originalNotes: originalNotes, ice: ice);
    final category = _cleanText(data['category'] as String? ?? '');
    final garnish = _cleanText(data['garnish'] as String? ?? '');
    final glass = _cleanText(data['glass'] as String? ?? '');
    final method = _cleanText(data['method'] as String? ?? '');
    final imageAssetPath = _cleanText(data['imageAssetPath'] as String? ?? '');
    final missingImage =
        data['missingImage'] as bool? ?? imageAssetPath.isEmpty;
    final reviewFlags = <String>[];
    if (garnish.isEmpty) {
      reviewFlags.add(
        'Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.',
      );
    }
    final ingredients = _parseCocktailIngredients(
      data['ingredients'],
      batchIndex: batchIndex,
    );
    for (final ingredient in ingredients.where(
      (item) => item.isBatchReference,
    )) {
      if ((ingredient.linkedBatchId ?? '').isEmpty) {
        reviewFlags.add(
          'Unresolved batch link for ${ingredient.ingredientName}. Match it to an approved batch before approval.',
        );
      }
    }
    return CocktailRecipe(
      id: _cleanText(data['id'] as String? ?? _slugify(name)),
      name: name,
      category: category,
      glassware: glass,
      garnish: garnish,
      method: method,
      notes: notes,
      ingredients: ingredients,
      sourceLabel: sourceLabel,
      needsReview: reviewFlags.isNotEmpty,
      reviewFlags: reviewFlags,
      isApproved: true,
      wasManuallyReviewed: true,
      imageAssetPath: imageAssetPath.isEmpty ? null : imageAssetPath,
      missingImage: missingImage,
      priceGbp:
          (data['priceGbp'] as num?)?.toDouble() ??
          approvedCocktailPriceGbpForName(name),
    );
  }

  BatchRecipe _linkBatchRecipe(BatchRecipe batch, List<BatchRecipe> batches) {
    final batchIndex = BatchGraphResolver.buildBatchIndex(
      batches.where((existing) => existing.id != batch.id),
    );
    return batch.copyWith(
      ingredients: batch.ingredients
          .map(
            (ingredient) => BatchGraphResolver.linkIngredientToBatch(
              ingredient: ingredient,
              batchIndex: batchIndex,
            ),
          )
          .toList(),
    );
  }

  List<RecipeIngredient> _parseBatchIngredients(Object? value) {
    final entries = value is List ? value : const [];
    return entries
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((entry) {
          final ingredientName = _cleanText(
            entry['ingredient'] as String? ?? '',
          );
          final amount = _cleanText(entry['amount'] as String? ?? '');
          return RecipeIngredient(
            ingredientName: ingredientName,
            measureMl: _parseMlAmount(amount),
            preparationNote: null,
          );
        })
        .where((ingredient) => ingredient.ingredientName.isNotEmpty)
        .toList();
  }

  List<RecipeIngredient> _parseCocktailIngredients(
    Object? value, {
    required Map<String, _BatchBlueprint> batchIndex,
  }) {
    final entries = value is List ? value : const [];
    return entries
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((entry) {
          final ingredientName = _cleanText(
            entry['ingredient'] as String? ?? '',
          );
          final amount = _cleanText(entry['amount'] as String? ?? '');
          final measureMl = _parseMlAmount(amount);
          final matchedBatch = batchIndex[_normalizeName(ingredientName)];
          final isBatchReference =
              matchedBatch != null ||
              BatchGraphResolver.looksLikeBatchReference(ingredientName);
          final preparationNote =
              amount.isEmpty ||
                  RegExp(
                    r'^\d+(?:\.\d+)?\s*ml$',
                    caseSensitive: false,
                  ).hasMatch(amount)
              ? null
              : 'Source amount: $amount';
          return RecipeIngredient(
            ingredientName: ingredientName,
            measureMl: measureMl,
            preparationNote: preparationNote,
            referenceType: isBatchReference
                ? IngredientReferenceType.batch
                : IngredientReferenceType.directIngredient,
            linkedBatchId: matchedBatch?.id,
          );
        })
        .where((ingredient) => ingredient.ingredientName.isNotEmpty)
        .toList();
  }

  double? _parseMlAmount(String amount) {
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*ml\b',
      caseSensitive: false,
    ).firstMatch(amount);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }

  String _composeNotes({required String originalNotes, required String ice}) {
    final parts = <String>[];
    if (originalNotes.isNotEmpty) {
      parts.add(originalNotes);
    }
    if (ice.isNotEmpty) {
      parts.add('Ice: $ice.');
    }
    return parts.join('\n');
  }

  String _existingConflictMessage(CuratedImportConflictMode mode) {
    return switch (mode) {
      CuratedImportConflictMode.skipExisting =>
        'Matches an existing venue item. This import mode will skip it on confirmation.',
      CuratedImportConflictMode.updateExisting =>
        'Matches an existing venue item. Confirming this import will update the live item instead of creating a duplicate.',
      CuratedImportConflictMode.importOnlyNew => '',
    };
  }

  static String _cleanText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeName(String value) {
    return _cleanText(value).toLowerCase();
  }

  CocktailRecipe? _findExistingCocktail({
    required Map<String, CocktailRecipe> lookup,
    required String name,
  }) {
    for (final key in _cocktailLookupKeys(name)) {
      final match = lookup[key];
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  Iterable<String> _cocktailLookupKeys(String value) sync* {
    final normalized = _normalizeName(value);
    if (normalized.isNotEmpty) {
      yield normalized;
    }
    final canonical = approvedCocktailNameMatchKey(value);
    if (canonical.isNotEmpty && canonical != normalized) {
      yield canonical;
    }
  }

  static String _slugify(String value) {
    return _normalizeName(
      value,
    ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

class _BatchBlueprint {
  const _BatchBlueprint({
    required this.id,
    required this.name,
    required this.category,
    required this.notes,
    required this.totalBatchVolumeMl,
    required this.ingredients,
    required this.aliases,
    required this.reviewFlags,
  });

  final String id;
  final String name;
  final String category;
  final String notes;
  final double? totalBatchVolumeMl;
  final List<RecipeIngredient> ingredients;
  final List<String> aliases;
  final List<String> reviewFlags;
}
