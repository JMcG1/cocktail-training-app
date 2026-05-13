import 'dart:convert';

import '../../domain/models/models.dart';

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

class CuratedRecipeImporter {
  static const sourceLabel = 'Curated cocktail specs dataset';
  static const assetPath = 'assets/data/cocktails.json';

  const CuratedRecipeImporter();

  CuratedImportPlan buildPlan({
    required String jsonText,
    required List<CocktailRecipe> existingRecipes,
    required CuratedImportConflictMode conflictMode,
  }) {
    final decoded = json.decode(jsonText);
    if (decoded is! List) {
      throw const FormatException('Curated cocktail dataset must be a top-level JSON list.');
    }

    final existingByName = <String, CocktailRecipe>{
      for (final recipe in existingRecipes) _normalizeName(recipe.name): recipe,
    };
    final drafts = <RecipeImportDraft>[];
    var totalRecipes = 0;
    var newRecipes = 0;
    var existingCount = 0;
    var skippedRecipes = 0;

    for (final entry in decoded) {
      if (entry is! Map) {
        continue;
      }
      final data = Map<String, dynamic>.from(entry);
      final name = _cleanText(data['name'] as String? ?? '');
      if (name.isEmpty) {
        continue;
      }
      totalRecipes += 1;
      final existing = existingByName[_normalizeName(name)];
      final isExisting = existing != null;
      if (isExisting) {
        existingCount += 1;
      } else {
        newRecipes += 1;
      }
      if (isExisting && conflictMode == CuratedImportConflictMode.importOnlyNew) {
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
        switch (conflictMode) {
          case CuratedImportConflictMode.skipExisting:
            skippedRecipes += 1;
            reviewFlags.add(
              'Matches an existing venue recipe. This import mode will skip it on confirmation.',
            );
          case CuratedImportConflictMode.updateExisting:
            reviewFlags.add(
              'Matches an existing venue recipe. Confirming this import will update the live recipe instead of creating a duplicate.',
            );
          case CuratedImportConflictMode.importOnlyNew:
            break;
        }
      }
      if (garnish.isEmpty) {
        reviewFlags.add(
          'Missing garnish in the curated OCR dataset. Review it against the original PDF before approval.',
        );
      }

      final id = isExisting && conflictMode == CuratedImportConflictMode.updateExisting
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
          ingredients: _parseIngredients(data['ingredients']),
          reviewFlags: reviewFlags,
          status: RecipeDraftStatus.pending,
          wasManuallyReviewed: false,
        ),
      );
    }

    final warnings = <String>[
      'Curated specs are loaded from $assetPath and still follow the no-invention rule.',
      if (existingCount > 0)
        switch (conflictMode) {
          CuratedImportConflictMode.skipExisting =>
            '$existingCount cocktail${existingCount == 1 ? '' : 's'} already exist in this venue and will be skipped when you confirm the import.',
          CuratedImportConflictMode.updateExisting =>
            '$existingCount cocktail${existingCount == 1 ? '' : 's'} already exist in this venue and will update in place when approved.',
          CuratedImportConflictMode.importOnlyNew =>
            '$existingCount existing cocktail match${existingCount == 1 ? '' : 'es'} were left out so you can review only new recipes.',
        },
    ];

    return CuratedImportPlan(
      importResult: RecipeImportResult(
        sourceName: sourceLabel,
        drafts: drafts,
        warnings: warnings,
        requiresOcr: false,
        rawText: jsonText,
        pageCount: decoded.length,
      ),
      conflictMode: conflictMode,
      totalRecipes: totalRecipes,
      newRecipes: newRecipes,
      existingRecipes: existingCount,
      skippedRecipes: skippedRecipes,
    );
  }

  List<RecipeIngredient> _parseIngredients(Object? value) {
    final entries = value is List ? value : const [];
    return entries
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((entry) {
          final ingredientName = _cleanText(entry['ingredient'] as String? ?? '');
          final amount = _cleanText(entry['amount'] as String? ?? '');
          final measureMl = _parseMlAmount(amount);
          final preparationNote = amount.isEmpty ||
                  RegExp(r'^\d+(?:\.\d+)?\s*ml$', caseSensitive: false).hasMatch(amount)
              ? null
              : 'Source amount: $amount';
          return RecipeIngredient(
            ingredientName: ingredientName,
            measureMl: measureMl,
            preparationNote: preparationNote,
          );
        })
        .where((ingredient) => ingredient.ingredientName.isNotEmpty)
        .toList();
  }

  double? _parseMlAmount(String amount) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*ml\b', caseSensitive: false).firstMatch(amount);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }

  String _composeNotes({
    required String originalNotes,
    required String ice,
  }) {
    final parts = <String>[];
    if (originalNotes.isNotEmpty) {
      parts.add(originalNotes);
    }
    if (ice.isNotEmpty) {
      parts.add('Ice: $ice.');
    }
    return parts.join('\n');
  }

  static String _cleanText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeName(String value) {
    return _cleanText(value).toLowerCase();
  }

  static String _slugify(String value) {
    return _normalizeName(value).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
