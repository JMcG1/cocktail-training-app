import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      expect(recipe['ingredients'], isA<List<dynamic>>());

      final id = recipe['id'] as String;
      expect(ids.add(id), isTrue, reason: 'Duplicate cocktail id: $id');

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
}
