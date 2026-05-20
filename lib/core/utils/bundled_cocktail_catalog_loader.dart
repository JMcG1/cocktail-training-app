import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/models.dart';
import 'curated_recipe_importer.dart';

class BundledCocktailCatalogLoader {
  BundledCocktailCatalogLoader._();

  static Future<VerifiedRecipeCatalog>? _cachedFuture;

  static Future<VerifiedRecipeCatalog> load() {
    return _cachedFuture ??= _loadInternal();
  }

  static Future<VerifiedRecipeCatalog> _loadInternal() async {
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
      return catalog;
    } catch (error, stackTrace) {
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
    developer.log(
      'Catalog asset load start asset=$assetKey',
      name: 'BundledCatalogLoader',
    );
    try {
      final text = await rootBundle.loadString(assetKey);
      developer.log(
        'Catalog asset load success asset=$assetKey source=rootBundle chars=${text.length}',
        name: 'BundledCatalogLoader',
      );
      return text;
    } catch (error, stackTrace) {
      developer.log(
        'Catalog asset rootBundle load failed asset=$assetKey',
        name: 'BundledCatalogLoader',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (!kIsWeb) {
        rethrow;
      }
    }

    final webPath = '/assets/$assetKey';
    developer.log(
      'Catalog asset web fallback start asset=$assetKey url=$webPath',
      name: 'BundledCatalogLoader',
    );
    final text = await NetworkAssetBundle(Uri.base).loadString(webPath);
    developer.log(
      'Catalog asset web fallback success asset=$assetKey url=$webPath chars=${text.length}',
      name: 'BundledCatalogLoader',
    );
    return text;
  }
}
