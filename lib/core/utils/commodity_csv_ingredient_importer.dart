import '../../domain/models/models.dart';

class CommodityIngredientImportResult {
  const CommodityIngredientImportResult({
    required this.matchedIngredients,
    required this.unmatchedIngredientNames,
  });

  final List<CommodityIngredientImportMatch> matchedIngredients;
  final List<String> unmatchedIngredientNames;
}

class CommodityIngredientImportMatch {
  const CommodityIngredientImportMatch({
    required this.ingredient,
    required this.sourceProductName,
  });

  final Ingredient ingredient;
  final String sourceProductName;

  double get bottleSizeMl => ingredient.bottleSizeMl;
  double get bottlePrice => ingredient.bottleCost;
}

class CommodityCsvIngredientImporter {
  const CommodityCsvIngredientImporter();

  CommodityIngredientImportResult buildImportPlan({
    required String csvText,
    required Iterable<Ingredient> ingredients,
    required Iterable<CocktailRecipe> recipes,
    required Iterable<BatchRecipe> batches,
  }) {
    final usedIngredientNames = <String>{
      for (final recipe in recipes)
        ...recipe.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
      for (final batch in batches)
        ...batch.ingredients
            .map((item) => item.ingredientName.trim())
            .where((name) => name.isNotEmpty),
    }.toList()..sort();

    final ingredientsByKey = {
      for (final ingredient in ingredients)
        _normalize(ingredient.name): ingredient,
    };
    final rows = _parseRows(csvText);
    final matchesByIngredientKey = <String, CommodityIngredientImportMatch>{};

    for (final row in rows) {
      for (final productAlias in _productAliasTargets.keys) {
        if (!_rowMatchesAlias(row.searchText, productAlias)) {
          continue;
        }
        final targets = _productAliasTargets[productAlias]!;
        for (final targetName in targets) {
          final ingredient = ingredientsByKey[_normalize(targetName)];
          if (ingredient == null) {
            continue;
          }
          matchesByIngredientKey[_normalize(
            ingredient.name,
          )] = CommodityIngredientImportMatch(
            ingredient: ingredient.copyWith(
              bottleSizeMl: row.bottleSizeMl,
              bottleCost: row.bottlePrice,
            ),
            sourceProductName: row.productName,
          );
        }
      }
    }

    final matchedIngredients = <CommodityIngredientImportMatch>[];
    final unmatchedIngredientNames = <String>[];

    for (final name in usedIngredientNames) {
      final key = _normalize(name);
      final match = matchesByIngredientKey[key];
      if (match != null) {
        matchedIngredients.add(match);
      } else {
        unmatchedIngredientNames.add(name);
      }
    }

    matchedIngredients.sort(
      (left, right) => left.ingredient.name.compareTo(right.ingredient.name),
    );

    return CommodityIngredientImportResult(
      matchedIngredients: matchedIngredients,
      unmatchedIngredientNames: unmatchedIngredientNames,
    );
  }

  bool _rowMatchesAlias(String searchText, String alias) {
    if (!searchText.contains(alias)) {
      return false;
    }
    if (alias == 'beefeater' && searchText.contains('pink')) {
      return false;
    }
    if (alias == 'bacardi superior' && searchText.contains('coconut')) {
      return false;
    }
    return true;
  }

  List<_CommodityRow> _parseRows(String csvText) {
    final records = _parseCsv(csvText);
    if (records.length < 2) {
      return const [];
    }
    final header = records.first;
    final productIndex = header.indexOf('ProductName');
    final packSizeIndex = header.indexOf('PackSize');
    final averagePriceIndex = header.indexOf('AveragePrice');
    if (productIndex < 0 || packSizeIndex < 0 || averagePriceIndex < 0) {
      return const [];
    }

    final rows = <_CommodityRow>[];
    for (final record in records.skip(1)) {
      if (record.length <= averagePriceIndex) {
        continue;
      }
      final productName = record[productIndex].trim();
      final packSizeText = record[packSizeIndex].trim();
      final averagePrice = double.tryParse(record[averagePriceIndex].trim());
      if (productName.isEmpty || averagePrice == null || averagePrice <= 0) {
        continue;
      }
      final sizeAndCount = _parseBottleSizeAndCount(
        packSizeText: packSizeText,
        productName: productName,
      );
      if (sizeAndCount == null) {
        continue;
      }
      rows.add(
        _CommodityRow(
          productName: productName,
          searchText: _normalize(productName),
          bottleSizeMl: sizeAndCount.unitSizeMl,
          bottlePrice: averagePrice / sizeAndCount.packCount,
        ),
      );
    }
    return rows;
  }

  _ParsedBottleSizeAndCount? _parseBottleSizeAndCount({
    required String packSizeText,
    required String productName,
  }) {
    final fromPackSize = _parseMeasurement(packSizeText);
    if (fromPackSize != null) {
      return fromPackSize;
    }
    return _parseMeasurement(productName);
  }

  _ParsedBottleSizeAndCount? _parseMeasurement(String text) {
    final normalized = text.toLowerCase().replaceAll(',', ' ');
    final packMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*[x]\s*(\d+(?:\.\d+)?)\s*(ml|cl|l|ltr|litre|litres|lit)\b',
    ).firstMatch(normalized);
    if (packMatch != null) {
      final packCount = double.tryParse(packMatch.group(1)!);
      final unitSize = double.tryParse(packMatch.group(2)!);
      final unit = packMatch.group(3)!;
      final unitSizeMl = _convertToMl(unitSize, unit);
      if (packCount != null && packCount > 0 && unitSizeMl > 0) {
        return _ParsedBottleSizeAndCount(
          unitSizeMl: unitSizeMl,
          packCount: packCount,
        );
      }
    }

    final singleMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(ml|cl|l|ltr|litre|litres|lit)\b',
    ).firstMatch(normalized);
    if (singleMatch != null) {
      final unitSize = double.tryParse(singleMatch.group(1)!);
      final unit = singleMatch.group(2)!;
      final unitSizeMl = _convertToMl(unitSize, unit);
      if (unitSizeMl > 0) {
        return _ParsedBottleSizeAndCount(unitSizeMl: unitSizeMl, packCount: 1);
      }
    }

    if (normalized.contains('litre') ||
        normalized.contains(' ltr') ||
        normalized.endsWith(' lit') ||
        normalized.endsWith(' l')) {
      return const _ParsedBottleSizeAndCount(unitSizeMl: 1000, packCount: 1);
    }
    return null;
  }

  double _convertToMl(double? amount, String unit) {
    if (amount == null || amount <= 0) {
      return 0;
    }
    switch (unit) {
      case 'ml':
        return amount;
      case 'cl':
        return amount * 10;
      case 'l':
      case 'ltr':
      case 'lit':
      case 'litre':
      case 'litres':
        return amount * 1000;
    }
    return 0;
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (char == '"') {
        final nextIsQuote = index + 1 < input.length && input[index + 1] == '"';
        if (inQuotes && nextIsQuote) {
          cell.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (!inQuotes && char == ',') {
        row.add(cell.toString());
        cell.clear();
        continue;
      }
      if (!inQuotes && (char == '\n' || char == '\r')) {
        if (char == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index += 1;
        }
        row.add(cell.toString());
        cell.clear();
        if (row.any((value) => value.isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
        continue;
      }
      cell.write(char);
    }

    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(List<String>.from(row));
    }
    return rows;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll('’', "'")
        .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _CommodityRow {
  const _CommodityRow({
    required this.productName,
    required this.searchText,
    required this.bottleSizeMl,
    required this.bottlePrice,
  });

  final String productName;
  final String searchText;
  final double bottleSizeMl;
  final double bottlePrice;
}

class _ParsedBottleSizeAndCount {
  const _ParsedBottleSizeAndCount({
    required this.unitSizeMl,
    required this.packCount,
  });

  final double unitSizeMl;
  final double packCount;
}

const Map<String, List<String>> _productAliasTargets = {
  '42 below vodka': ['42 Below Vodka'],
  'absolut vanilla': ['Absolut Vanilia', 'Absolut Vanilla Vodka'],
  'amaretto disaronno': ['Giffard Amaretto'],
  'angostura bitters': ['Angostura Bitters'],
  'aperol': ['Aperol'],
  'bacardi caribbean spiced': ['Bacardi Carribean', 'Bacardi Spiced Rum'],
  'bacardi coconut': ['Bacardi Coconut'],
  'bacardi superior': ['Bacardi Superior'],
  'beefeater pink': ['Beefeater Pink', 'Beefeater Pink Gin'],
  'beefeater': ['Beefeater Gin'],
  'belvoir elderflower': ['Belvoir Elderflower'],
  'blend coffee liq': ['Coffee Liqueur'],
  'blend passionfru': ['Blend Passionfruit Liqueur'],
  'botivo': ['Botivo'],
  'campari': ['Campari'],
  'cazcabel blanco': ['Cazcabel Blanco Tequila', 'Cazcabel Tequila'],
  'cazcabel coffee': ['Cazcabel Coffee'],
  'cazcabel honey': ['Cazcabel Honey'],
  'el hispano jalapeno liquor': ['El Hispano Jalapeno Liquor'],
  'giff agave syrup': ['Giffard Agave Syrup'],
  'giff coconut sirop': ['Giffard Coconut Syrup'],
  'giff creme de mure': ['Creme de Mure'],
  'giff fraise liqueur': ['Giffard Strawberry Liqueur'],
  'giff fraise sirop': ['Giffard Strawberry Syrup'],
  'giff gomme': ['Giffard Gomme', 'Gomme'],
  'giff lychee liqueur': ['Giffard Lychee Liqueur'],
  'giff passionfruit sirop': ['Giffard Passionfruit Syrup'],
  'giff raspberry sirop': ['Raspberry Syrup'],
  'giff vanilla sirop': ['Giffard Vanilla Syrup'],
  'giff watermelon sirop': ['Giffard Watermelon Syrup', 'Watermelon Syrup'],
  'giffard na elderflower liqueur': ['Giffard N/A Elderflower Liqueur'],
  'giffard triple sec': ['Giffard Triple Sec'],
  'hendricks': ['Hendricks Gin'],
  'isolabella limoncello': ['Limoncello'],
  'jamesons': ['Jameson Whiskey'],
  'kraken': ['Kraken Rum'],
  'lemon juice': ['Lemon Juice'],
  'lillet rose': ['Lillet Rose Vermouth'],
  'lime juice': ['Lime Juice'],
  'makers mark': ['Maker\'s Mark Bourbon'],
  'martini rosso': ['Martini Rosso'],
  'melonade': ['Melonade'],
  'monin passion fruit puree': ['Monin Passionfruit Puree'],
  'ms betters foamer': ['MS Better Foamer'],
  'rose prosecco': ['Rose Prosecco'],
  'sea change 0': ['Sea Change 0% Sparkling Wine'],
  'schweppes lemonade bib': ['Schweppes Lemonade'],
  'schweppes ginger beer': ['Schweppes Ginger Beer'],
  'simpatico prosecco': ['Simpatico Prosecco', 'Prosecco'],
  'solo concentrate': ['Solo Coffee'],
  'st germain': ['St Germain'],
  'sunpride cranberry': ['Cranberry Juice'],
  'sunpride orange': ['Orange Juice'],
  'sunpride pineapple': ['Pineapple Juice'],
  'the pickle house spiced tomato': [
    'Pickle House Bloody Mary Spiced Mix',
    'Pickle House Mary Mix',
  ],
};
