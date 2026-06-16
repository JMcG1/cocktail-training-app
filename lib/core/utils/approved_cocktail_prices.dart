const Map<String, double> _sourcePricesByName = {
  'Flower Power 75': 11.75,
  'Bramble Plant Pot': 11.95,
  'Palm House Colada': 13.50,
  'Spicy Margarita': 13.75,
  'The Botanista Cosmo': 11.50,
  'Tomatini Plant Pot': 11.95,
  'Botany Bay Rum Punch': 13.50,
  'Garden Gimlet': 11.50,
  'The Lawnstar Martini': 13.50,
  'The Botanist Ultimate G&T': 14.50,
  'Aperol Spritz': 11.75,
  'Limoncello Spritz': 11.75,
  'Hugo Spritz': 11.95,
  'Watermelon Spritz': 11.75,
  'Strawberry Shrub Spritz': 11.75,
  'Classic Mojito': 11.75,
  'Dark & Stormy': 12.50,
  'Classic Margarita': 11.75,
  'Classic Negroni': 11.25,
  'The Bloody Botanist': 12.50,
  'Amaretto Sour': 10.95,
  'Espresso Martini': 12.95,
  'Paloma': 11.50,
  'Raspberry Martini': 11.50,
  'Pornstar Martini': 12.95,
  'Classic Old Fashioned': 12.50,
  'Veneto Spritz': 7.50,
  'Garden Mary': 6.95,
  'Homemade Lemonade': 5.25,
  'Hu-No Spritz': 7.50,
  'Botanist Mule': 7.80,
  'Passionfruit Iced Tea': 7.25,
  'Watermelon Cooler': 7.50,
};

const Map<String, String> _sourceAliasToCanonicalName = {
  'Botanista Cosmo': 'The Botanista Cosmo',
  'Lawnstar Martini': 'The Lawnstar Martini',
  'Old Fashioned': 'Classic Old Fashioned',
  'Botany Bay Rum P': 'Botany Bay Rum Punch',
  'Bramble Plant Po': 'Bramble Plant Pot',
  'Passionfruit Ice': 'Passionfruit Iced Tea',
  'Picante Margarita': 'Spicy Margarita',
  'Palmhouse Colada': 'Palm House Colada',
  'Bloody Botanist': 'The Bloody Botanist',
  'Apernol Spritz': 'Veneto Spritz',
  'Clover Club': 'Raspberry Martini',
};

const List<String> approvedCocktailPriceSourceGaps = [
  "Pimm's & Lemonade",
  'Irish Coffee',
  'Long Island Iced Tea',
  'Mimosa',
];

final Map<String, double> _sourcePricesByKey = {
  for (final entry in _sourcePricesByName.entries)
    _normalizeApprovedCocktailPriceKey(entry.key): entry.value,
};

final Map<String, String> _sourceAliasesByKey = {
  for (final entry in _sourceAliasToCanonicalName.entries)
    _normalizeApprovedCocktailPriceKey(entry.key):
        _normalizeApprovedCocktailPriceKey(entry.value),
};

double? approvedCocktailPriceGbpForName(String name) {
  final exact = _sourcePricesByKey[approvedCocktailNameMatchKey(name)];
  if (exact != null) {
    return exact;
  }
  for (final key in _priceLookupKeys(name)) {
    final fallback = _sourcePricesByKey[_sourceAliasesByKey[key] ?? key];
    if (fallback != null) {
      return fallback;
    }
  }
  return null;
}

List<String> approvedCocktailPriceCoverageGaps(Iterable<String> names) {
  final missing =
      names
          .where((name) => approvedCocktailPriceGbpForName(name) == null)
          .toSet()
          .toList()
        ..sort();
  return missing;
}

String approvedCocktailNameMatchKey(String name) {
  for (final key in _priceLookupKeys(name)) {
    final canonicalKey = _sourceAliasesByKey[key] ?? key;
    if (_sourcePricesByKey.containsKey(canonicalKey)) {
      return canonicalKey;
    }
  }
  return _normalizeApprovedCocktailPriceKey(name);
}

bool approvedCocktailNamesMatch(String left, String right) {
  final leftKey = approvedCocktailNameMatchKey(left);
  final rightKey = approvedCocktailNameMatchKey(right);
  if (leftKey == rightKey) {
    return true;
  }
  return _normalizeApprovedCocktailPriceKey(left) ==
      _normalizeApprovedCocktailPriceKey(right);
}

Iterable<String> _priceLookupKeys(String name) sync* {
  final normalized = _normalizeApprovedCocktailPriceKey(name);
  if (normalized.isEmpty) {
    return;
  }
  final seen = <String>{};
  if (seen.add(normalized)) {
    yield normalized;
  }
  if (normalized.startsWith('the ')) {
    final withoutThe = normalized.substring(4);
    if (seen.add(withoutThe)) {
      yield withoutThe;
    }
  }
}

String _normalizeApprovedCocktailPriceKey(String value) {
  return value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll('™', ' ')
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
