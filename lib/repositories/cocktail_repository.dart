import 'dart:convert';

import 'package:cocktail_training/models/cocktail.dart';
import 'package:flutter/services.dart';

class CocktailRepository {
  const CocktailRepository();

  Future<List<Cocktail>> loadCocktails() async {
    final payload = await rootBundle.loadString('assets/data/cocktails.json');
    final decoded = jsonDecode(payload) as List<dynamic>;

    return decoded
        .map((entry) => Cocktail.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }
}
