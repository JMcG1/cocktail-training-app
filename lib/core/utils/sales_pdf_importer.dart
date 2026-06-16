import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../domain/models/models.dart';
import 'approved_cocktail_prices.dart';

class SalesPdfImporter {
  const SalesPdfImporter();

  SalesPdfImportPreview extractForBartender({
    required Uint8List bytes,
    required String fileName,
    required String bartenderName,
    required WeeklyConcernSession session,
    required List<CocktailRecipe> approvedRecipes,
  }) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final pages = <String>[];
      for (var index = 0; index < document.pages.count; index += 1) {
        final text = extractor
            .extractText(
              startPageIndex: index,
              endPageIndex: index,
              layoutText: true,
            )
            .trim();
        if (text.isNotEmpty) {
          pages.add(text);
        }
      }
      return parseTextForBartender(
        text: pages.join('\n\n'),
        sourceName: fileName,
        bartenderName: bartenderName,
        session: session,
        approvedRecipes: approvedRecipes,
      );
    } finally {
      document.dispose();
    }
  }

  SalesPdfImportPreview parseTextForBartender({
    required String text,
    required String sourceName,
    required String bartenderName,
    required WeeklyConcernSession session,
    required List<CocktailRecipe> approvedRecipes,
  }) {
    final allowedRecipes = approvedRecipes
        .where((recipe) => session.targetCocktailIds.contains(recipe.id))
        .where((recipe) => recipe.priceGbp != null && recipe.priceGbp! > 0)
        .toList();
    final warnings = <String>[];
    final ignoredProducts = <String>{};
    final dateSelection = _extractDateSelection(text);

    if (allowedRecipes.isEmpty) {
      return SalesPdfImportPreview(
        sourceName: sourceName,
        bartenderName: bartenderName,
        dateSelection: dateSelection,
        entries: const [],
        usedFallbackQuantities: false,
        ignoredProducts: const [],
        warnings: const [
          'The selected stock-focus session does not have any priced target cocktails yet, so there is nothing to import from the PDF.',
        ],
      );
    }

    final totalsByRecipeId = <String, double>{};
    String? matchedReportName;
    final bartenderTokens = _normalizedTokens(bartenderName);

    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || _shouldSkipLine(line)) {
        continue;
      }

      final row = _parseSalesRow(line);
      if (row == null) {
        continue;
      }

      final match = _extractProductForBartender(
        prefix: row.prefix,
        bartenderTokens: bartenderTokens,
      );
      if (match == null) {
        continue;
      }

      matchedReportName ??= match.employeeName;
      final recipe = _matchRecipe(match.productName, allowedRecipes);
      if (recipe == null) {
        ignoredProducts.add(match.productName);
        continue;
      }

      final value = row.totalValue > 0 ? row.totalValue : row.wetValue;
      if (value <= 0) {
        continue;
      }
      totalsByRecipeId.update(recipe.id, (existing) => existing + value, ifAbsent: () => value);
    }

    if (totalsByRecipeId.isEmpty) {
      warnings.add(
        'No employee name in the PDF matched $bartenderName, so the importer filled each target cocktail with 25 sales for testing.',
      );
      return SalesPdfImportPreview(
        sourceName: sourceName,
        bartenderName: bartenderName,
        dateSelection: dateSelection,
        entries: allowedRecipes
            .map(
              (recipe) => BartenderSalesEntry(
                cocktailId: recipe.id,
                cocktailName: recipe.name,
                quantitySold: 25,
              ),
            )
            .toList(),
        usedFallbackQuantities: true,
        ignoredProducts: ignoredProducts.toList()..sort(),
        warnings: warnings,
      );
    }

    final entries = allowedRecipes
        .where((recipe) => totalsByRecipeId.containsKey(recipe.id))
        .map((recipe) {
          final price = recipe.priceGbp!;
          final estimatedQuantity = (totalsByRecipeId[recipe.id]! / price).round();
          return BartenderSalesEntry(
            cocktailId: recipe.id,
            cocktailName: recipe.name,
            quantitySold: estimatedQuantity < 0 ? 0 : estimatedQuantity,
          );
        })
        .where((entry) => entry.quantitySold > 0)
        .toList()
      ..sort((a, b) => a.cocktailName.compareTo(b.cocktailName));

    if (entries.isEmpty) {
      warnings.add(
        'A matching employee name was found, but none of the priced target cocktails for this session appeared in the PDF.',
      );
    }

    return SalesPdfImportPreview(
      sourceName: sourceName,
      bartenderName: bartenderName,
      matchedReportName: matchedReportName,
      dateSelection: dateSelection,
      entries: entries,
      usedFallbackQuantities: false,
      ignoredProducts: ignoredProducts.toList()..sort(),
      warnings: warnings,
    );
  }

  String? _extractDateSelection(String text) {
    final match = RegExp(r'Date Selection:\s*(.+)').firstMatch(text);
    return match?.group(1)?.trim();
  }

  bool _shouldSkipLine(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('product sales by employee') ||
        lower.startsWith('date selection:') ||
        lower.startsWith('calendar :') ||
        lower.startsWith('product :') ||
        lower.startsWith('estate :') ||
        lower.startsWith('order destination :') ||
        lower.startsWith('section:') ||
        lower.startsWith('measure:') ||
        lower.startsWith('employee product portion') ||
        lower.startsWith('printed:') ||
        lower.startsWith('subtotal');
  }

  _SalesRow? _parseSalesRow(String line) {
    const portions = [
      'Standard',
      'Double',
      'Half',
      'Splash',
      'Top',
      'As Main',
      '125ml',
      '175ml',
      '250ml',
      'Large Glass',
    ];
    final portionPattern = portions.map(RegExp.escape).join('|');
    final match = RegExp(
      '^(.*?)\\s+($portionPattern)\\s+(-?[\\d,]+\\.\\d{2})\\s+(-?[\\d,]+\\.\\d{2})\\s+(-?[\\d,]+\\.\\d{2})\\s+(-?[\\d,]+\\.\\d{2})\$',
    ).firstMatch(line);
    if (match == null) {
      return null;
    }
    return _SalesRow(
      prefix: (match.group(1) ?? '').trim(),
      wetValue: _parseMoney(match.group(5) ?? '0'),
      totalValue: _parseMoney(match.group(6) ?? '0'),
    );
  }

  _EmployeeProductMatch? _extractProductForBartender({
    required String prefix,
    required List<String> bartenderTokens,
  }) {
    final rawTokens = prefix.split(RegExp(r'\s+'));
    final normalizedTokens = rawTokens.map(_normalizeToken).toList();
    if (bartenderTokens.isEmpty || rawTokens.length <= bartenderTokens.length) {
      return null;
    }
    if (normalizedTokens.length < bartenderTokens.length) {
      return null;
    }
    for (var index = 0; index < bartenderTokens.length; index += 1) {
      if (normalizedTokens[index] != bartenderTokens[index]) {
        return null;
      }
    }
    final employeeName = rawTokens.take(bartenderTokens.length).join(' ').trim();
    final productName = rawTokens.skip(bartenderTokens.length).join(' ').trim();
    if (productName.isEmpty) {
      return null;
    }
    return _EmployeeProductMatch(
      employeeName: employeeName,
      productName: productName,
    );
  }

  CocktailRecipe? _matchRecipe(
    String reportProductName,
    List<CocktailRecipe> allowedRecipes,
  ) {
    final reportKey = approvedCocktailNameMatchKey(reportProductName);
    CocktailRecipe? bestRecipe;
    var bestScore = 0.0;

    for (final recipe in allowedRecipes) {
      final recipeKey = approvedCocktailNameMatchKey(recipe.name);
      if (recipeKey == reportKey) {
        return recipe;
      }
      final score = _prefixScore(reportKey, recipeKey);
      if (score > bestScore) {
        bestScore = score;
        bestRecipe = recipe;
      }
    }

    if (bestScore >= 0.82) {
      return bestRecipe;
    }
    return null;
  }

  double _prefixScore(String left, String right) {
    if (left == right) {
      return 1;
    }
    if (left.isEmpty || right.isEmpty) {
      return 0;
    }
    if (left.startsWith(right) || right.startsWith(left)) {
      final shorter = left.length < right.length ? left.length : right.length;
      final longer = left.length > right.length ? left.length : right.length;
      return shorter / longer;
    }

    final leftWords = left.split(' ');
    final rightWords = right.split(' ');
    var shared = 0;
    final count = leftWords.length < rightWords.length
        ? leftWords.length
        : rightWords.length;
    for (var index = 0; index < count; index += 1) {
      if (leftWords[index] == rightWords[index]) {
        shared += 1;
      } else {
        break;
      }
    }
    if (shared == 0) {
      return 0;
    }
    final longerWords = leftWords.length > rightWords.length
        ? leftWords.length
        : rightWords.length;
    return shared / longerWords;
  }

  List<String> _normalizedTokens(String value) {
    return value
        .split(RegExp(r'\s+'))
        .map(_normalizeToken)
        .where((token) => token.isNotEmpty)
        .toList();
  }

  String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  double _parseMoney(String raw) {
    return double.tryParse(raw.replaceAll(',', '')) ?? 0;
  }
}

class _SalesRow {
  const _SalesRow({
    required this.prefix,
    required this.wetValue,
    required this.totalValue,
  });

  final String prefix;
  final double wetValue;
  final double totalValue;
}

class _EmployeeProductMatch {
  const _EmployeeProductMatch({
    required this.employeeName,
    required this.productName,
  });

  final String employeeName;
  final String productName;
}
