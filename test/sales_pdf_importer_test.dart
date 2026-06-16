import 'package:flutter_test/flutter_test.dart';

import 'package:stock_variance_coach/core/utils/sales_pdf_importer.dart';
import 'package:stock_variance_coach/domain/models/models.dart';

void main() {
  const importer = SalesPdfImporter();
  final session = WeeklyConcernSession(
    id: 'week-1',
    label: 'Vodka and spritz focus',
    weekStart: DateTime(2026, 6, 8),
    concerns: const [],
    targetCocktailIds: const [
      'aperol-spritz',
      'bramble-plant-pot',
      'classic-mojito',
    ],
    bartenderSales: const [],
    quizSessionIds: const [],
  );
  const recipes = [
    CocktailRecipe(
      id: 'aperol-spritz',
      name: 'Aperol Spritz',
      category: 'Spritz',
      glassware: 'Wine glass',
      garnish: 'Orange',
      method: 'Build',
      notes: '',
      ingredients: [],
      sourceLabel: 'test',
      needsReview: false,
      reviewFlags: [],
      isApproved: true,
      wasManuallyReviewed: true,
      priceGbp: 11.75,
    ),
    CocktailRecipe(
      id: 'bramble-plant-pot',
      name: 'Bramble Plant Pot',
      category: 'Signature',
      glassware: 'Plant pot',
      garnish: 'Mint',
      method: 'Build',
      notes: '',
      ingredients: [],
      sourceLabel: 'test',
      needsReview: false,
      reviewFlags: [],
      isApproved: true,
      wasManuallyReviewed: true,
      priceGbp: 11.95,
    ),
    CocktailRecipe(
      id: 'classic-mojito',
      name: 'Classic Mojito',
      category: 'Classics',
      glassware: 'Highball',
      garnish: 'Mint',
      method: 'Build',
      notes: '',
      ingredients: [],
      sourceLabel: 'test',
      needsReview: false,
      reviewFlags: [],
      isApproved: true,
      wasManuallyReviewed: true,
      priceGbp: 11.75,
    ),
  ];

  test('imports only matched target cocktails for selected bartender', () {
    const text = '''
Product Sales by Employee
Date Selection: 08/06/2026 - 14/06/2026
Employee Product Portion Food Gift Cards Wet Total
Adela Friedrichova Aperol Spritz Standard 0.00 0.00 11.75 11.75
Adela Friedrichova Appletiser Bottl Standard 0.00 0.00 7.50 7.50
Adela Friedrichova Bramble Plant Po Standard 0.00 0.00 107.55 107.55
Adela Friedrichova Classic Mojito Standard 0.00 0.00 70.50 70.50
Baillie Stewart Aperol Spritz Standard 0.00 0.00 35.25 35.25
Printed: 15/06/2026 16:53 Page: 1 of 49
''';

    final preview = importer.parseTextForBartender(
      text: text,
      sourceName: 'sales by employee.pdf',
      bartenderName: 'Adela Friedrichova',
      session: session,
      approvedRecipes: recipes,
    );

    expect(preview.matchedReportName, 'Adela Friedrichova');
    expect(preview.usedFallbackQuantities, isFalse);
    expect(preview.dateSelection, '08/06/2026 - 14/06/2026');
    expect(preview.entries, hasLength(3));
    expect(
      preview.entries.firstWhere((entry) => entry.cocktailId == 'aperol-spritz').quantitySold,
      1,
    );
    expect(
      preview.entries.firstWhere((entry) => entry.cocktailId == 'bramble-plant-pot').quantitySold,
      9,
    );
    expect(
      preview.entries.firstWhere((entry) => entry.cocktailId == 'classic-mojito').quantitySold,
      6,
    );
  });

  test('uses fallback test quantities when bartender name is missing', () {
    const text = '''
Product Sales by Employee
Date Selection: 08/06/2026 - 14/06/2026
Employee Product Portion Food Gift Cards Wet Total
Adela Friedrichova Aperol Spritz Standard 0.00 0.00 11.75 11.75
''';

    final preview = importer.parseTextForBartender(
      text: text,
      sourceName: 'sales by employee.pdf',
      bartenderName: 'Jaime McGovern',
      session: session,
      approvedRecipes: recipes,
    );

    expect(preview.usedFallbackQuantities, isTrue);
    expect(preview.entries, hasLength(3));
    expect(preview.entries.every((entry) => entry.quantitySold == 25), isTrue);
    expect(
      preview.warnings.single,
      contains('filled each target cocktail with 25 sales'),
    );
  });
}
