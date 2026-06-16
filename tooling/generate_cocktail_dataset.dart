import 'dart:convert';
import 'dart:io';

import 'package:stock_variance_coach/core/utils/approved_cocktail_prices.dart';

void main() async {
  final sourceDir = Directory('ocr_output/cocktail_specs_2026');
  if (!sourceDir.existsSync()) {
    stderr.writeln('OCR source directory not found: ${sourceDir.path}');
    exitCode = 1;
    return;
  }

  final pageFiles =
      sourceDir
          .listSync()
          .whereType<File>()
          .where(
            (file) => RegExp(r'^page-\d+\.txt$').hasMatch(_basename(file.path)),
          )
          .toList()
        ..sort((a, b) => _pageNumber(a.path).compareTo(_pageNumber(b.path)));

  final recipePages = <int, String>{};
  for (final file in pageFiles) {
    final raw = await file.readAsString();
    if (raw.toUpperCase().contains('INGREDIENTS & VOLUMES')) {
      recipePages[_pageNumber(file.path)] = raw;
    }
  }

  final expectedPages = _recipes.map((recipe) => recipe.page).toSet();
  final detectedPages = recipePages.keys.toSet();
  final unexpectedPages = detectedPages.difference(expectedPages).toList()
    ..sort();
  final missingPages = expectedPages.difference(detectedPages).toList()..sort();
  if (missingPages.isNotEmpty) {
    stderr.writeln(
      'Recipe page mismatch. Expected ${expectedPages.toList()..sort()} but found ${recipePages.keys.toList()..sort()}.',
    );
    exitCode = 1;
    return;
  }

  final sourceWarnings = <String>[];
  if (unexpectedPages.isNotEmpty) {
    sourceWarnings.add(
      'Additional OCR pages with recipe-style layout were detected and ignored for this export: ${unexpectedPages.join(', ')}.',
    );
  }
  for (final recipe in _recipes) {
    final pageText = recipePages[recipe.page]!.toLowerCase();
    for (final phrase in recipe.sourceChecks) {
      if (!pageText.contains(phrase.toLowerCase())) {
        sourceWarnings.add(
          'Page ${recipe.page}: expected OCR marker "$phrase" was not found while validating ${recipe.name}.',
        );
      }
    }
  }

  final outputDir = Directory('assets/data')..createSync(recursive: true);
  final outputFile = File('${outputDir.path}/cocktails.json');
  final reviewFile = File('tooling/ocr_recipe_review.md');

  final jsonPayload = const JsonEncoder.withIndent(
    '  ',
  ).convert(_recipes.map((recipe) => recipe.toJson()).toList());
  await outputFile.writeAsString('$jsonPayload\n');

  final decoded = jsonDecode(await outputFile.readAsString());
  if (decoded is! List) {
    stderr.writeln('Generated JSON is not a top-level list.');
    exitCode = 1;
    return;
  }

  final ids = <String>{};
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) {
      stderr.writeln('Generated JSON contains a non-object entry.');
      exitCode = 1;
      return;
    }
    for (final key in [
      'id',
      'name',
      'ingredients',
      'method',
      'glass',
      'garnish',
      'ice',
    ]) {
      if (!item.containsKey(key)) {
        stderr.writeln('Generated JSON entry is missing "$key".');
        exitCode = 1;
        return;
      }
    }
    final id = item['id'] as String;
    if (!ids.add(id)) {
      stderr.writeln('Duplicate recipe id detected: $id');
      exitCode = 1;
      return;
    }
  }

  final missingPrices = approvedCocktailPriceCoverageGaps(
    _recipes.map((recipe) => recipe.name),
  );
  if (missingPrices.length != approvedCocktailPriceSourceGaps.length ||
      !missingPrices.every(approvedCocktailPriceSourceGaps.contains)) {
    stderr.writeln(
      'Unexpected cocktail price coverage gaps: ${missingPrices.join(', ')}',
    );
    exitCode = 1;
    return;
  }

  final missingFieldLines = <String>[];
  final lowConfidenceLines = <String>[];
  for (final recipe in _recipes) {
    final missing = <String>[];
    if (recipe.garnish.trim().isEmpty) {
      missing.add('garnish');
    }
    if (recipe.glass.trim().isEmpty) {
      missing.add('glass');
    }
    if (recipe.ice.trim().isEmpty) {
      missing.add('ice');
    }
    if (missing.isNotEmpty) {
      missingFieldLines.add(
        '- `${recipe.name}` (page ${recipe.page}): missing ${missing.join(', ')}.',
      );
    }
    if (recipe.lowConfidenceReasons.isNotEmpty) {
      lowConfidenceLines.add(
        '- `${recipe.name}` (page ${recipe.page}): ${recipe.lowConfidenceReasons.join(' ')}',
      );
    }
  }

  final review = StringBuffer()
    ..writeln('# OCR Recipe Review')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Source folder: `ocr_output/cocktail_specs_2026/`')
    ..writeln('- OCR page text files read: ${pageFiles.length}')
    ..writeln(
      '- Recipe specification pages detected automatically: ${recipePages.length}',
    )
    ..writeln('- Structured recipes exported: ${_recipes.length}')
    ..writeln('- JSON output: `assets/data/cocktails.json`')
    ..writeln()
    ..writeln('## Validation')
    ..writeln('- JSON decoded successfully as a top-level list.')
    ..writeln('- All recipe ids are unique.')
    ..writeln(
      '- Each entry includes `id`, `name`, `ingredients`, `method`, `glass`, `garnish`, and `ice`.',
    )
    ..writeln(
      '- The dataset is stored under `assets/data/` for Flutter asset loading.',
    )
    ..writeln()
    ..writeln('## Recipes With Missing Or Conflicting Fields');

  if (missingFieldLines.isEmpty) {
    review.writeln('- No required dataset fields are blank after curation.');
  } else {
    for (final line in missingFieldLines) {
      review.writeln(line);
    }
  }

  review
    ..writeln()
    ..writeln('## Low-Confidence OCR Sections');

  if (lowConfidenceLines.isEmpty && sourceWarnings.isEmpty) {
    review.writeln('- No low-confidence sections were flagged.');
  } else {
    for (final line in lowConfidenceLines) {
      review.writeln(line);
    }
    for (final line in sourceWarnings) {
      review.writeln('- $line');
    }
  }

  review
    ..writeln()
    ..writeln('## Page Coverage')
    ..writeln('| Page | Cocktail | Category |')
    ..writeln('| --- | --- | --- |');
  for (final recipe in _recipes) {
    review.writeln('| ${recipe.page} | ${recipe.name} | ${recipe.category} |');
  }

  await reviewFile.writeAsString(review.toString());

  stdout.writeln('Generated ${_recipes.length} recipes.');
  stdout.writeln('Wrote ${outputFile.path}');
  stdout.writeln('Wrote ${reviewFile.path}');
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

int _pageNumber(String path) {
  final match = RegExp(r'page-(\d+)\.txt$').firstMatch(_basename(path));
  return int.parse(match!.group(1)!);
}

class _RecipeSpec {
  const _RecipeSpec({
    required this.page,
    required this.id,
    required this.name,
    required this.category,
    required this.ingredients,
    required this.method,
    required this.glass,
    required this.garnish,
    required this.ice,
    this.notes = '',
    this.imageAssetPath,
    this.lowConfidenceReasons = const [],
    this.sourceChecks = const [],
  });

  final int page;
  final String id;
  final String name;
  final String category;
  final List<Map<String, String>> ingredients;
  final String method;
  final String glass;
  final String garnish;
  final String ice;
  final String notes;
  final String? imageAssetPath;
  final List<String> lowConfidenceReasons;
  final List<String> sourceChecks;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'priceGbp': approvedCocktailPriceGbpForName(name),
    'ingredients': ingredients,
    'method': method,
    'glass': glass,
    'garnish': garnish,
    'ice': ice,
    'notes': notes,
    'imageAssetPath': imageAssetPath ?? 'assets/cocktails/$id.png',
    'missingImage': false,
    'sourcePage': page,
  };
}

const _recipes = <_RecipeSpec>[
  _RecipeSpec(
    page: 3,
    id: 'aperol-spritz',
    name: 'Aperol Spritz',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Aperol', 'amount': '40ml'},
      {'ingredient': 'Simpatico Prosecco', 'amount': '70ml'},
      {'ingredient': 'Soda', 'amount': '50ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Orange slice',
    ice: 'Cubed',
    sourceChecks: ['aperol 40ml', 'prosecco 70ml', 'orange slice x1'],
  ),
  _RecipeSpec(
    page: 4,
    id: 'limoncello-spritz',
    name: 'Limoncello Spritz',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Limoncello Spritz Batch', 'amount': '50ml'},
      {'ingredient': 'Lemon Juice', 'amount': '20ml'},
      {'ingredient': 'Simpatico Prosecco', 'amount': '40ml'},
      {'ingredient': 'Soda Water', 'amount': '80ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Rosemary sprig and lemon wheel',
    ice: 'Cubed',
    sourceChecks: ['limoncello spritz batch', 'lemon juice', 'rosemary sprig'],
  ),
  _RecipeSpec(
    page: 5,
    id: 'strawberry-shrub-spritz',
    name: 'Strawberry Shrub Spritz',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Strawberry Fizz Batch', 'amount': '60ml'},
      {'ingredient': 'Pink Prosecco', 'amount': '40ml'},
      {'ingredient': 'Soda Water', 'amount': '80ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Half strawberry and strawberry vodka atomizer spray',
    ice: 'Cubed',
    notes: 'Spritz with strawberry vodka atomizer for a fragrant finish.',
    lowConfidenceReasons: [
      'The ingredient table was noisier than the method block, so prosecco and soda volumes were confirmed from the method steps.',
    ],
    sourceChecks: ['strawberry fizz batch', 'pink prosecco', 'soda water'],
  ),
  _RecipeSpec(
    page: 6,
    id: 'hugo-spritz',
    name: 'Hugo Spritz',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'St Germain', 'amount': '40ml'},
      {'ingredient': 'Belvoir Elderflower', 'amount': '20ml'},
      {'ingredient': 'Lemon Juice', 'amount': '20ml'},
      {'ingredient': 'Soda', 'amount': '75ml'},
      {'ingredient': 'Prosecco', 'amount': '40ml'},
      {'ingredient': 'Mint', 'amount': '1 sprig'},
    ],
    method: 'Build and stir',
    glass: 'Wine Glass',
    garnish: 'Mint sprig',
    ice: 'Cubed',
    notes: 'Express the mint before adding it to the drink.',
    lowConfidenceReasons: [
      'The garnish line merged into the method block, so the mint garnish was recovered from the serving instructions.',
    ],
    sourceChecks: ['st germain', 'belvoir elderflower', 'mint portion'],
  ),
  _RecipeSpec(
    page: 7,
    id: 'watermelon-spritz',
    name: 'Watermelon Spritz',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Watermelon Spritz Batch', 'amount': '75ml'},
      {'ingredient': 'Watermelon Juice', 'amount': '50ml'},
      {'ingredient': 'Watermelon Syrup', 'amount': '10ml'},
      {'ingredient': 'Simpatico Prosecco', 'amount': '40ml'},
      {'ingredient': 'Soda Water', 'amount': '30ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Watermelon slice',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The ingredient table reads "Cantaloupe Batch" while the method block reads "Watermelon Spritz Batch"; the final dataset follows the method block and recipe title.',
    ],
    sourceChecks: ['watermelon juice', 'watermelon syrup', 'watermelon slice'],
  ),
  _RecipeSpec(
    page: 8,
    id: 'the-lawnstar-martini',
    name: 'The Lawnstar Martini',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Lawnstar Batch', 'amount': '70ml'},
      {'ingredient': 'Cranberry Juice', 'amount': '20ml'},
      {'ingredient': 'Cucumber', 'amount': '2 slices'},
      {'ingredient': 'Rose Prosecco', 'amount': '25ml'},
    ],
    method: 'Shake and double strain',
    glass: 'Coupe Glass',
    garnish: 'Half strawberry on the side of the shot glass',
    ice: 'Cubed',
    notes:
        'Serve 25ml rose prosecco in a separate shot glass and finish with two sprays of strawberry vodka atomizer.',
    lowConfidenceReasons: [
      'The shot-glass prosecco serve and atomizer finish only appeared clearly in the method block, not the ingredient table.',
    ],
    sourceChecks: ['lawnstar batch', 'cranberry juice', 'cucumber'],
  ),
  _RecipeSpec(
    page: 9,
    id: 'flower-power-75',
    name: 'Flower Power 75',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Flower Power Batch', 'amount': '60ml'},
      {'ingredient': 'Lemon Juice', 'amount': '15ml'},
      {'ingredient': 'Rose Prosecco', 'amount': '40ml'},
    ],
    method: 'Shake and double strain',
    glass: 'Coupe Glass',
    garnish: '2 viola flowers',
    ice: 'Cubed',
    notes:
        'Pre-pour the prosecco into the chilled coupe and finish with two sprays of jasmine vodka atomizer.',
    sourceChecks: ['flower power batch', 'lemon juice', 'viola flowers'],
  ),
  _RecipeSpec(
    page: 10,
    id: 'tomatini-plant-pot',
    name: 'Tomatini Plant Pot',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Tomatini Plant Batch', 'amount': '70ml'},
      {'ingredient': 'Apple Juice', 'amount': '10ml'},
      {'ingredient': 'Saline', 'amount': '2 dashes'},
      {'ingredient': 'Cucumber', 'amount': '2 slices'},
    ],
    method: 'Shake and strain',
    glass: 'Plant Pot',
    garnish: '2 cherry tomatoes on the vine, mint sprig, and cucumber slice',
    ice: 'Cubed with crushed ice cap',
    notes: 'Top the serve with a crushed-ice cap for texture.',
    sourceChecks: ['tomatini plant batch', 'apple juice', 'saline'],
  ),
  _RecipeSpec(
    page: 11,
    id: 'bramble-plant-pot',
    name: 'Bramble Plant Pot',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Beefeater Pink', 'amount': '30ml'},
      {'ingredient': 'Raspberry Syrup', 'amount': '10ml'},
      {'ingredient': 'Lemon Juice', 'amount': '20ml'},
      {'ingredient': 'Fresh Raspberries', 'amount': '2'},
      {'ingredient': 'Creme de Mure', 'amount': '20ml'},
    ],
    method: 'Build and muddle',
    glass: 'Plant Pot',
    garnish: '2 fresh raspberries and mint sprig',
    ice: 'Crushed',
    sourceChecks: ['beefeater pink', 'raspberry syrup', 'creme de mure'],
  ),
  _RecipeSpec(
    page: 12,
    id: 'picante-margarita',
    name: 'Picante Margarita',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Spicy Margarita Batch', 'amount': '45ml'},
      {'ingredient': 'El Hispano Jalapeno Liquor', 'amount': '5ml'},
      {'ingredient': 'Giffard Agave Syrup', 'amount': '10ml'},
      {'ingredient': 'Pineapple Juice', 'amount': '20ml'},
      {'ingredient': 'Lime Juice', 'amount': '15ml'},
    ],
    method: 'Shake and strain',
    glass: 'Old Fashioned',
    garnish:
        'Mini Tabasco bottle, 2 chilli pineapple triangles, and coriander oil drizzle',
    ice: 'Cubed',
    notes: 'Serve on a cookie dough wooden board.',
    sourceChecks: ['spicy margarita batch', 'jalape', 'pineapple juice'],
  ),
  _RecipeSpec(
    page: 13,
    id: 'garden-gimlet',
    name: 'Garden Gimlet',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Cucumber Gin', 'amount': '50ml'},
      {'ingredient': 'Lime & Elderflower Cordial', 'amount': '20ml'},
      {'ingredient': 'Sugar Syrup', 'amount': '5ml'},
      {'ingredient': 'Lime Juice', 'amount': '15ml'},
      {'ingredient': 'Red Vein Sorrel', 'amount': '10 leaves'},
    ],
    method: 'Churn',
    glass: 'Botany Flask',
    garnish: '3 red vein sorrel leaves',
    ice: 'Crushed',
    lowConfidenceReasons: [
      'Sugar syrup only appears clearly in the method block, so it was added from the service steps rather than the ingredient table.',
    ],
    sourceChecks: ['cucumber gin', 'elderflower cordial', 'red vein sorrel'],
  ),
  _RecipeSpec(
    page: 14,
    id: 'the-botanista-cosmo',
    name: 'The Botanista Cosmo',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Botanista Cosmo Batch', 'amount': '50ml'},
      {'ingredient': 'Cranberry Juice', 'amount': '30ml'},
      {'ingredient': 'Lime Juice', 'amount': '15ml'},
    ],
    method: 'Shake and double strain',
    glass: 'Coupe Glass',
    garnish: 'Watermelon wedge',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The OCR rendered the lime measure as "145ML"; the recipe image and method layout confirm 15ml.',
    ],
    sourceChecks: [
      'botanista cosmo batch',
      'cranberry juice',
      'watermelon wedge',
    ],
  ),
  _RecipeSpec(
    page: 15,
    id: 'botany-bay-rum-punch',
    name: 'Botany Bay Rum Punch',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Botany Punch Batch', 'amount': '75ml'},
      {'ingredient': 'Monin Passionfruit Puree', 'amount': '15ml'},
      {'ingredient': 'Pineapple Juice', 'amount': '60ml'},
      {'ingredient': 'Lime Juice', 'amount': '15ml'},
      {'ingredient': 'Angostura Bitters', 'amount': '2 dashes'},
    ],
    method: 'Shake and strain',
    glass: 'Tiki Ceramic',
    garnish:
        'Viola flower, pineapple leaf, pineapple wedge, and half orange slice',
    ice: 'Cubed with crushed ice cap',
    notes: 'Cap the drink with crushed ice after straining.',
    sourceChecks: [
      'botany punch batch',
      'passionfruit puree',
      'angostura bitters',
    ],
  ),
  _RecipeSpec(
    page: 16,
    id: 'palmhouse-colada',
    name: 'Palmhouse Colada',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Palmhouse Colada Batch', 'amount': '125ml'},
      {'ingredient': 'Soda', 'amount': '25ml'},
    ],
    method: 'Build',
    glass: 'Twisted Old Fashioned',
    garnish: 'Pineapple wedge and 2 pineapple leaves',
    ice: 'Cubed',
    notes: 'A clarified pina colada-style milk punch serve.',
    lowConfidenceReasons: [
      'The OCR clipped the soda line, so the 25ml soda serve was confirmed against the source page artwork.',
    ],
    sourceChecks: [
      'palmhouse colada batch',
      'pineapple wedge',
      'pineapple leaf',
    ],
  ),
  _RecipeSpec(
    page: 17,
    id: 'the-botanist-ultimate-gt',
    name: 'The Botanist Ultimate G&T',
    category: 'Signature Cocktails',
    ingredients: [
      {'ingredient': 'Hepple Gin', 'amount': '50ml'},
      {'ingredient': 'Fever-Tree Tonic Water', 'amount': '200ml'},
    ],
    method: 'Build',
    glass: 'Ambassador Gin Balloon',
    garnish: 'Lemon wedge and bay leaf',
    ice: 'Cubed',
    sourceChecks: ['hepple gin', 'tonic water', 'bay leaf'],
  ),
  _RecipeSpec(
    page: 18,
    id: 'espresso-martini',
    name: 'Espresso Martini',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': '42 Below Vodka', 'amount': '40ml'},
      {'ingredient': 'Coffee Liqueur', 'amount': '25ml'},
      {'ingredient': 'Solo Coffee', 'amount': '25ml'},
      {'ingredient': 'Giffard Vanilla Syrup', 'amount': '5ml'},
    ],
    method: 'Shake and double strain',
    glass: 'Coupe Glass',
    garnish: '3 espresso beans',
    ice: 'Cubed',
    sourceChecks: ['42 below vodka', 'coffee liqueur', 'espresso beans'],
  ),
  _RecipeSpec(
    page: 19,
    id: 'pornstar-martini',
    name: 'Pornstar Martini',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Absolut Vanilla Vodka', 'amount': '40ml'},
      {'ingredient': 'Monin Passionfruit Puree', 'amount': '20ml'},
      {'ingredient': 'Lime Juice', 'amount': '10ml'},
      {'ingredient': 'Blend Passionfruit Liqueur', 'amount': '10ml'},
      {'ingredient': 'Giffard Vanilla Syrup', 'amount': '5ml'},
      {'ingredient': 'Pineapple Juice', 'amount': '20ml'},
      {'ingredient': 'Prosecco', 'amount': '25ml'},
    ],
    method: 'Shake and double strain',
    glass: 'Coupe Glass',
    garnish: '',
    ice: 'Cubed',
    notes: 'Serve the prosecco as a separate 25ml side shot.',
    lowConfidenceReasons: [
      'Several ingredient amounts were noisy in the OCR, and no garnish was listed on the page, so the serve keeps the garnish field blank and flags the recipe for review.',
    ],
    sourceChecks: ['passionfruit puree', 'pineapple juice', 'prosecco'],
  ),
  _RecipeSpec(
    page: 20,
    id: 'classic-mojito',
    name: 'Classic Mojito',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Bacardi Superior', 'amount': '50ml'},
      {'ingredient': 'Lime Juice', 'amount': '25ml'},
      {'ingredient': 'Giffard Gomme', 'amount': '20ml'},
      {'ingredient': 'Mint Leaves', 'amount': '10'},
      {'ingredient': 'Soda Postmix', 'amount': 'Top'},
    ],
    method: 'Build and churn',
    glass: 'Highball',
    garnish: 'Mint sprig',
    ice: 'Crushed',
    sourceChecks: ['bacardi superior', 'mint leaves', 'mint sprig'],
  ),
  _RecipeSpec(
    page: 21,
    id: 'dark-and-stormy',
    name: 'Dark and Stormy',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Goslings Black Seal Rum', 'amount': '50ml'},
      {'ingredient': 'Lime Juice', 'amount': '15ml'},
      {'ingredient': 'Giffard Gomme', 'amount': '5ml'},
      {'ingredient': 'Angostura Bitters', 'amount': '1 dash'},
      {'ingredient': 'Schweppes Ginger Beer', 'amount': '100ml'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Lime wedge, cucumber ribbon, and mint sprig',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The lime amount was partially obscured in the ingredient table, so 15ml was confirmed from the method block.',
    ],
    sourceChecks: ['goslings black seal', 'ginger beer', 'cucumber ribbon'],
  ),
  _RecipeSpec(
    page: 22,
    id: 'amaretto-sour',
    name: 'Amaretto Sour',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Giffard Amaretto', 'amount': '50ml'},
      {'ingredient': 'Lemon Juice', 'amount': '25ml'},
      {'ingredient': 'MS Better Foamer', 'amount': '4 dashes'},
    ],
    method: 'Shake and strain',
    glass: 'Rocks Glass',
    garnish: 'Maraschino cherry and lemon wedge',
    ice: 'Cubed',
    sourceChecks: ['amaretto', 'lemon juice', 'maraschino cherry'],
  ),
  _RecipeSpec(
    page: 23,
    id: 'raspberry-martini',
    name: 'Raspberry Martini',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Beefeater Pink Gin', 'amount': '50ml'},
      {'ingredient': 'Lemon Juice', 'amount': '25ml'},
      {'ingredient': 'Giffard Gomme', 'amount': '15ml'},
      {'ingredient': 'Giffard Strawberry Syrup', 'amount': '10ml'},
      {'ingredient': 'Raspberries', 'amount': '3'},
      {'ingredient': 'MS Better Foamer', 'amount': '4 dashes'},
    ],
    method: 'Shake and fine strain',
    glass: 'Coupe Glass',
    garnish: 'Raspberry',
    ice: 'Cubed',
    imageAssetPath: 'assets/cocktails/clover-club.png',
    lowConfidenceReasons: [
      'The OCR page title reads like "Raspberry Martini", and this dataset now follows that page title.',
    ],
    sourceChecks: ['beefeater pink gin', 'strawberry syrup', 'raspberry'],
  ),
  _RecipeSpec(
    page: 24,
    id: 'classic-negroni',
    name: 'Classic Negroni',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Beefeater Gin', 'amount': '30ml'},
      {'ingredient': 'Martini Rosso', 'amount': '25ml'},
      {'ingredient': 'Campari', 'amount': '20ml'},
    ],
    method: 'Stir and strain',
    glass: 'Twisted Old Fashioned',
    garnish: 'Orange slice',
    ice: 'Cubed',
    sourceChecks: ['beefeater gin', 'martini rosso', 'campari'],
  ),
  _RecipeSpec(
    page: 25,
    id: 'paloma',
    name: 'Paloma',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Cazcabel Blanco Tequila', 'amount': '40ml'},
      {'ingredient': 'Lime Juice', 'amount': '10ml'},
      {'ingredient': 'Giffard Agave Syrup', 'amount': '5ml'},
      {'ingredient': 'Fever-Tree Grapefruit Soda', 'amount': '100ml'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Salt rim and lime wedge',
    ice: 'Cubed',
    sourceChecks: ['cazcabel blanco tequila', 'grapefruit soda', 'salt rim'],
  ),
  _RecipeSpec(
    page: 26,
    id: 'bloody-botanist',
    name: 'Bloody Botanist',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': '42 Below Vodka', 'amount': '50ml'},
      {'ingredient': 'Lemon Juice', 'amount': '10ml'},
      {'ingredient': 'Pickle House Bloody Mary Spiced Mix', 'amount': '100ml'},
    ],
    method: 'Build and stir',
    glass: 'Highball',
    garnish: 'Dehydrated tomato slice and celery stick',
    ice: 'Cubed',
    sourceChecks: ['42 below vodka', 'pickle house', 'celery stick'],
  ),
  _RecipeSpec(
    page: 27,
    id: 'classic-margarita',
    name: 'Classic Margarita',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': 'Cazcabel Blanco Tequila', 'amount': '40ml'},
      {'ingredient': 'Lime Juice', 'amount': '20ml'},
      {'ingredient': 'Giffard Triple Sec', 'amount': '20ml'},
      {'ingredient': 'Giffard Agave Syrup', 'amount': '5ml'},
    ],
    method: 'Shake and fine strain',
    glass: 'Coupe',
    garnish: 'Half salt rim and lime wedge',
    ice: 'Cubed',
    notes: 'Can be served on the rocks in an old fashioned glass if requested.',
    sourceChecks: ['triple sec', 'agave syrup', 'half salt rim'],
  ),
  _RecipeSpec(
    page: 28,
    id: 'classic-old-fashioned',
    name: 'Classic Old Fashioned',
    category: 'Classic Cocktails',
    ingredients: [
      {'ingredient': "Maker's Mark Bourbon", 'amount': '50ml'},
      {'ingredient': 'Homemade Demerara Syrup', 'amount': '7.5ml'},
      {'ingredient': 'Angostura Bitters', 'amount': '3 dashes'},
    ],
    method: 'Stir',
    glass: 'Twisted Old Fashioned',
    garnish: 'Orange twist',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The ingredient table clipped the bourbon line, so the spirit name was recovered from the method instructions.',
    ],
    sourceChecks: ['demerara syrup', 'angostura bitters', 'orange twist'],
  ),
  _RecipeSpec(
    page: 29,
    id: 'pimms-and-lemonade',
    name: "Pimm's & Lemonade",
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': "Pimm's", 'amount': '50ml'},
      {'ingredient': 'Schweppes Lemonade', 'amount': '120ml'},
    ],
    method: 'Build',
    glass: 'Wine Glass',
    garnish: 'Lemon wedge, half strawberry, cucumber slice, and mint sprig',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The OCR title reads "LEMOMADE"; the final name is corrected to "Lemonade".',
    ],
    sourceChecks: ['pimms', 'schweppes lemonade', 'half strawberry'],
  ),
  _RecipeSpec(
    page: 30,
    id: 'irish-coffee',
    name: 'Irish Coffee',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Jameson Whiskey', 'amount': '40ml'},
      {'ingredient': 'Single Espresso Shot', 'amount': '40ml'},
      {'ingredient': 'Giffard Gomme', 'amount': '15ml'},
      {'ingredient': 'Boiling Water', 'amount': '30ml'},
      {'ingredient': 'Cold Double Cream', 'amount': '40ml'},
    ],
    method: 'Build and layer',
    glass: 'Irish Coffee Glass',
    garnish: 'Grated nutmeg',
    ice: 'None',
    lowConfidenceReasons: [
      'The method OCR briefly read the sugar line as "145ML"; the ingredient table confirms a 15ml gomme serve.',
    ],
    sourceChecks: ['jameson whiskey', 'grated nutmeg'],
  ),
  _RecipeSpec(
    page: 31,
    id: 'long-island-iced-tea',
    name: 'Long Island Iced Tea',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': '42 Below Vodka', 'amount': '10ml'},
      {'ingredient': 'Beefeater Gin', 'amount': '10ml'},
      {'ingredient': 'Bacardi Superior', 'amount': '10ml'},
      {'ingredient': 'Cazcabel Blanco Tequila', 'amount': '10ml'},
      {'ingredient': 'Giffard Triple Sec', 'amount': '10ml'},
      {'ingredient': 'Lemon Juice', 'amount': '15ml'},
      {'ingredient': 'Coca-Cola', 'amount': 'Top'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Lemon slice',
    ice: 'Cubed',
    sourceChecks: ['42 below vodka', 'coca cola', 'lemon slice x1'],
  ),
  _RecipeSpec(
    page: 32,
    id: 'mimosa',
    name: 'Mimosa',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Orange Juice', 'amount': '50ml'},
      {'ingredient': 'Simpatico Prosecco', 'amount': '75ml'},
    ],
    method: 'Build',
    glass: 'Flute',
    garnish: 'None',
    ice: 'None',
    sourceChecks: ['orange juice', 'simpatico prosecco', 'none'],
  ),
  _RecipeSpec(
    page: 33,
    id: 'homemade-lemonade',
    name: 'Homemade Lemonade',
    category: 'Spritz Off Main Menu',
    ingredients: [
      {'ingredient': 'Lemon Juice', 'amount': '30ml'},
      {'ingredient': 'Giffard Gomme', 'amount': '20ml'},
      {'ingredient': 'Tap Water', 'amount': '100ml'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Lemon wedge',
    ice: 'Cubed',
    sourceChecks: ['tap water', 'lemon wedge', '100ml'],
  ),
  _RecipeSpec(
    page: 34,
    id: 'passionfruit-iced-tea',
    name: 'Passionfruit Iced Tea',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': 'Cold Brew Earl Grey Tea', 'amount': '120ml'},
      {'ingredient': 'Giffard Passionfruit Syrup', 'amount': '25ml'},
      {'ingredient': 'Lemon Juice', 'amount': '10ml'},
    ],
    method: 'Build and stir',
    glass: 'Old Fashioned Glass',
    garnish: 'Lemon slice, cucumber slice, and mint sprig',
    ice: 'Cubed',
    sourceChecks: ['earl grey tea', 'passionfruit syrup', 'mint sprig'],
  ),
  _RecipeSpec(
    page: 35,
    id: 'hu-no-spritz',
    name: 'Hu-No Spritz',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': 'Giffard N/A Elderflower Liqueur', 'amount': '35ml'},
      {'ingredient': 'Sea Change 0% Sparkling Wine', 'amount': '75ml'},
      {'ingredient': 'Soda Water', 'amount': '40ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Viola flower and lemon wedge',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The OCR text dropped the title, so the recipe name and garnish were confirmed against the source page image.',
    ],
    sourceChecks: ['elderflower liqueur', 'sea change 0% sparkling wine'],
  ),
  _RecipeSpec(
    page: 36,
    id: 'apernol-spritz',
    name: 'Apernol Spritz',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': "Lyre's Italian Spritz", 'amount': '35ml'},
      {'ingredient': 'Sea Change 0% Sparkling Wine', 'amount': '75ml'},
      {'ingredient': 'Soda Water', 'amount': '40ml'},
    ],
    method: 'Build',
    glass: 'Spritz Glass',
    garnish: 'Orange slice and non-alcoholic straw',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The OCR text lost the title and part of the garnish line, so the final name and garnish were image-verified.',
    ],
    sourceChecks: ['lyre', 'sea change 0% sparkling wine'],
  ),
  _RecipeSpec(
    page: 37,
    id: 'botanist-mule',
    name: 'Botanist Mule',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': 'Botivo', 'amount': '30ml'},
      {'ingredient': 'Lime Juice', 'amount': '12.5ml'},
      {'ingredient': 'Schweppes Ginger Beer', 'amount': '200ml bottle'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Lime wedge, cucumber slice, mint sprig, and non-alcoholic straw',
    ice: 'Cubed',
    lowConfidenceReasons: [
      'The OCR clipped the bottle serve note, so the 200ml ginger beer bottle measure was cross-checked with the page image.',
    ],
    sourceChecks: ['botivo', '12.5ml', 'ginger beer'],
  ),
  _RecipeSpec(
    page: 38,
    id: 'watermelon-cooler',
    name: 'Watermelon Cooler',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': 'Watermelon Juice', 'amount': '50ml'},
      {'ingredient': 'Giffard Watermelon Syrup', 'amount': '20ml'},
      {'ingredient': 'Lime Juice', 'amount': '10ml'},
      {'ingredient': 'Soda', 'amount': '100ml'},
    ],
    method: 'Build',
    glass: 'Highball',
    garnish: 'Watermelon wedge, mint sprig, and non-alcoholic straw',
    ice: 'Crushed',
    lowConfidenceReasons: [
      'The page title and glassware were confirmed from the source image because the OCR text partially dropped them.',
    ],
    sourceChecks: ['watermelon juice', 'watermelon syrup', 'soda 100ml'],
  ),
  _RecipeSpec(
    page: 39,
    id: 'garden-mary',
    name: 'Garden Mary',
    category: 'Non-Alc Cocktails',
    ingredients: [
      {'ingredient': 'Pickle House Mary Mix', 'amount': '200ml'},
      {'ingredient': 'Lemon Juice', 'amount': '10ml'},
    ],
    method: 'Build and stir',
    glass: 'Old Fashioned Glass',
    garnish: 'Celery stick and lemon slice',
    ice: 'Cubed',
    sourceChecks: ['pickle house mary mix', 'lemon juice', 'celery stick'],
  ),
];
