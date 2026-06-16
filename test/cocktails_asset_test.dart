import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/approved_cocktail_prices.dart';

void main() {
  test('cocktail asset JSON stays valid and app-friendly', () async {
    final file = File('assets/data/cocktails.json');
    expect(file.existsSync(), isTrue);

    final decoded = jsonDecode(await file.readAsString());
    expect(decoded, isA<List<dynamic>>());

    final recipes = decoded as List<dynamic>;
    expect(recipes, isNotEmpty);

    final ids = <String>{};
    for (final item in recipes) {
      expect(item, isA<Map<String, dynamic>>());
      final recipe = item as Map<String, dynamic>;
      expect(recipe['id'], isA<String>());
      expect(recipe['name'], isA<String>());
      expect(recipe['category'], isA<String>());
      expect(recipe['method'], isA<String>());
      expect(recipe['glass'], isA<String>());
      expect(recipe['garnish'], isA<String>());
      expect(recipe['ice'], isA<String>());
      expect(recipe['notes'], isA<String>());
      expect(recipe['missingImage'], isA<bool>());
      expect(recipe.containsKey('priceGbp'), isTrue);
      expect(recipe['priceGbp'], anyOf(isNull, isA<num>()));
      expect(
        recipe['priceGbp'],
        approvedCocktailPriceGbpForName(recipe['name'] as String),
      );
      expect(recipe['ingredients'], isA<List<dynamic>>());

      final id = recipe['id'] as String;
      expect(ids.add(id), isTrue, reason: 'Duplicate cocktail id: $id');
      expect(recipe['sourcePage'], isA<int>());

      final imageAssetPath = recipe['imageAssetPath'] as String?;
      final missingImage = recipe['missingImage'] as bool;
      expect(
        (imageAssetPath?.trim().isNotEmpty ?? false) || missingImage,
        isTrue,
        reason: 'Recipe must have an image asset or missingImage flag: $id',
      );
      if (!missingImage && imageAssetPath != null) {
        expect(
          File(imageAssetPath).existsSync(),
          isTrue,
          reason: 'Missing referenced image asset for $id: $imageAssetPath',
        );
      }

      final ingredients = recipe['ingredients'] as List<dynamic>;
      expect(ingredients, isNotEmpty, reason: 'Recipe has no ingredients: $id');

      for (final ingredient in ingredients) {
        expect(ingredient, isA<Map<String, dynamic>>());
        final entry = ingredient as Map<String, dynamic>;
        expect(entry['ingredient'], isA<String>());
        expect(entry['amount'], isA<String>());
        expect((entry['ingredient'] as String).trim(), isNotEmpty);
        expect((entry['amount'] as String).trim(), isNotEmpty);
      }
    }
  });

  test('approved cocktail price coverage stays explicit', () async {
    final file = File('assets/data/cocktails.json');
    final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
    final missingPrices = approvedCocktailPriceCoverageGaps(
      decoded
          .map((item) => (item as Map<String, dynamic>)['name'] as String)
          .toList(),
    );

    expect(missingPrices, unorderedEquals(approvedCocktailPriceSourceGaps));
  });

  test('price lookup handles source aliases and truncated names safely', () {
    expect(approvedCocktailPriceGbpForName('Botanista Cosmo'), 11.50);
    expect(approvedCocktailPriceGbpForName('Lawnstar Martini'), 13.50);
    expect(approvedCocktailPriceGbpForName('Old Fashioned'), 12.50);
    expect(approvedCocktailPriceGbpForName('Botany Bay Rum P'), 13.50);
    expect(approvedCocktailPriceGbpForName('Bramble Plant Po'), 11.95);
    expect(approvedCocktailPriceGbpForName('Passionfruit Ice'), 7.25);
    expect(approvedCocktailPriceGbpForName('Picante Margarita'), 13.75);
    expect(approvedCocktailPriceGbpForName('Palmhouse Colada'), 13.50);
    expect(approvedCocktailPriceGbpForName('Bloody Botanist'), 12.50);
    expect(approvedCocktailPriceGbpForName('Apernol Spritz'), 7.50);
  });

  test('batch asset JSON stays valid and app-friendly', () async {
    final file = File('assets/data/batches.json');
    expect(file.existsSync(), isTrue);

    final decoded = jsonDecode(await file.readAsString());
    expect(decoded, isA<List<dynamic>>());

    final batches = decoded as List<dynamic>;
    expect(batches, isNotEmpty);

    final ids = <String>{};
    for (final item in batches) {
      expect(item, isA<Map<String, dynamic>>());
      final batch = item as Map<String, dynamic>;
      expect(batch['id'], isA<String>());
      expect(batch['name'], isA<String>());
      expect(batch['category'], isA<String>());
      expect(batch['notes'], isA<String>());
      expect(batch['ingredients'], isA<List<dynamic>>());

      final id = batch['id'] as String;
      expect(ids.add(id), isTrue, reason: 'Duplicate batch id: $id');

      final ingredients = batch['ingredients'] as List<dynamic>;
      expect(ingredients, isNotEmpty, reason: 'Batch has no ingredients: $id');

      for (final ingredient in ingredients) {
        expect(ingredient, isA<Map<String, dynamic>>());
        final entry = ingredient as Map<String, dynamic>;
        expect(entry['ingredient'], isA<String>());
        expect(entry['amount'], isA<String>());
        expect((entry['ingredient'] as String).trim(), isNotEmpty);
        expect((entry['amount'] as String).trim(), isNotEmpty);
      }
    }
  });
}
