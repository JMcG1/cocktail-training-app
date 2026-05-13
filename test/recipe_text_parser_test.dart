import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/recipe_text_parser.dart';

void main() {
  group('RecipeTextParser OCR filtering', () {
    test('excludes non-cocktail utility pages from OCR imports', () {
      const source = '''
===== PAGE 2 =====
CLASSIC COCKTAILS HOMEMADE INGREDIENTS - 39
ESPRESSO MARTINI - 16 HOMEMADE LEMONADE - 30

===== PAGE 18 =====
DESCRIPTION
INGREDIENTS & VOLUMES
VODKA 40ml
METHOD & SPEC NOTES
SHAKE WITH ICE.
GARNISH
COFFEE BEANS

===== PAGE 32 =====
DESCRIPTION
INGREDIENTS & VOLUMES
LEMON JUICE 30ml
GIFFARD GOMME 20ml
TAP WATER 100ml
METHOD & SPEC NOTES
BUILD IN A HIGHBALL GLASS.
GARNISH
LEMON WEDGE
''';

      final result = RecipeTextParser().parseImportText(
        source: source,
        sourceName: 'ocr.txt',
      );

      expect(result.drafts.map((draft) => draft.name), ['ESPRESSO MARTINI']);
      expect(
        result.drafts.single.category,
        anyOf('Classic Cocktails', isEmpty),
      );
    });
  });
}
