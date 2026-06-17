import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'approved_cocktail_prices.dart';
import 'asset_text_loader.dart';
import 'curated_recipe_importer.dart';

class BundledCatalogDiagnostics {
  const BundledCatalogDiagnostics({
    this.loaded = false,
    this.source = 'unattempted',
    this.cocktailCount = 0,
    this.batchCount = 0,
    this.firstCocktailName,
    this.lastError,
    this.attemptedPaths = const [],
  });

  final bool loaded;
  final String source;
  final int cocktailCount;
  final int batchCount;
  final String? firstCocktailName;
  final String? lastError;
  final List<String> attemptedPaths;

  BundledCatalogDiagnostics copyWith({
    bool? loaded,
    String? source,
    int? cocktailCount,
    int? batchCount,
    Object? firstCocktailName = _bundledNoChange,
    Object? lastError = _bundledNoChange,
    List<String>? attemptedPaths,
  }) {
    return BundledCatalogDiagnostics(
      loaded: loaded ?? this.loaded,
      source: source ?? this.source,
      cocktailCount: cocktailCount ?? this.cocktailCount,
      batchCount: batchCount ?? this.batchCount,
      firstCocktailName: identical(firstCocktailName, _bundledNoChange)
          ? this.firstCocktailName
          : firstCocktailName as String?,
      lastError: identical(lastError, _bundledNoChange)
          ? this.lastError
          : lastError as String?,
      attemptedPaths: attemptedPaths ?? this.attemptedPaths,
    );
  }
}

const Object _bundledNoChange = Object();

class BundledCocktailCatalogLoader {
  BundledCocktailCatalogLoader._();

  static Future<VerifiedRecipeCatalog>? _cachedFuture;
  static BundledCatalogDiagnostics _lastDiagnostics =
      const BundledCatalogDiagnostics();

  static BundledCatalogDiagnostics get lastDiagnostics => _lastDiagnostics;

  @visibleForTesting
  static void debugResetCache() {
    _cachedFuture = null;
    _lastDiagnostics = const BundledCatalogDiagnostics();
  }

  static Future<VerifiedRecipeCatalog> load() {
    return _cachedFuture ??= _loadInternal();
  }

  static Future<VerifiedRecipeCatalog> _loadInternal() async {
    _lastDiagnostics = const BundledCatalogDiagnostics(
      loaded: false,
      source: 'starting',
      attemptedPaths: [],
    );
    developer.log(
      'Bundled cocktail catalog load start',
      name: 'BundledCatalogLoader',
    );
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
      developer.log(
        'Bundled cocktail catalog parsed cocktails=${catalog.recipes.length} batches=${catalog.batches.length} first=${catalog.recipes.isEmpty ? '<none>' : catalog.recipes.first.name}',
        name: 'BundledCatalogLoader',
      );
      final missingPrices = approvedCocktailPriceCoverageGaps(
        catalog.recipes.map((recipe) => recipe.name),
      );
      if (missingPrices.isNotEmpty) {
        developer.log(
          'Bundled cocktail catalog has recipes without a source-backed price: ${missingPrices.join(', ')}',
          name: 'BundledCatalogLoader',
          level: 900,
        );
      }
      _lastDiagnostics = _lastDiagnostics.copyWith(
        loaded: true,
        source: _lastDiagnostics.source == 'starting'
            ? 'rootBundle'
            : _lastDiagnostics.source,
        cocktailCount: catalog.recipes.length,
        batchCount: catalog.batches.length,
        firstCocktailName: catalog.recipes.isEmpty
            ? null
            : catalog.recipes.first.name,
        lastError: null,
      );
      return catalog;
    } catch (error, stackTrace) {
      _lastDiagnostics = _lastDiagnostics.copyWith(
        loaded: false,
        source: _lastDiagnostics.source == 'starting'
            ? 'failed'
            : _lastDiagnostics.source,
        lastError: error.toString(),
      );
      developer.log(
        'Bundled cocktail catalog load failed',
        name: 'BundledCatalogLoader',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Cocktail list could not be loaded. Please refresh or contact admin.',
      );
    }
  }

  static Future<String> _loadAssetText(String assetKey) async {
    _lastDiagnostics = _lastDiagnostics.copyWith(
      attemptedPaths: [..._lastDiagnostics.attemptedPaths, assetKey],
    );
    final text = await loadBundledAssetText(
      assetKey,
      logName: 'BundledCatalogLoader',
    );
    _lastDiagnostics = _lastDiagnostics.copyWith(
      source: kIsWeb ? 'web-fallback' : 'filesystem',
      lastError: null,
    );
    return text;
  }
}
