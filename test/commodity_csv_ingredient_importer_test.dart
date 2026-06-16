import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/utils/commodity_csv_ingredient_importer.dart';
import 'package:stock_variance_coach/domain/models/models.dart';

void main() {
  const importer = CommodityCsvIngredientImporter();

  group('CommodityCsvIngredientImporter', () {
    test(
      'matches approved ingredients and converts pack prices to single bottle prices',
      () {
        const csv = '''
Outlet Name,CompanyName,SupplierName,ProductName,ProductReference,Category,Subcategory,Unit,PackSize,UnitQuantity,OrderCount,TotalPrice,AveragePrice
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,42 BELOW VODKA - 70cl Bot,353301450,Spirits,Vodka,ml,70cl Bot,42.000,4,716.04,17.05
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,ABSOLUT VANILLA - 70cl Bot,35320547,Spirits,Vodka,ml,70cl Bot,30.000,5,541.20,18.04
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,BEEFEATER PINK - 70cl Bot,32020247,Spirits,Gin,ml,70cl Bot,48.000,4,745.44,15.53
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,MAKERS MARK - 70cl Bot,30242747,Spirits,Whisky,ml,70cl Bot,12.000,2,270.12,22.51
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,MARTINI ROSSO - 75 cl,48010048,Vermouth/sherry/port,Verm/sherry/port,ml,EA,2.000,2,20.69,10.34
Botanist Edinburgh,New World Trading Company,Oliver Kay (Bar),LEMON JUICE - SINGLE - BAR - 6 x 1L,15825,Liquor Purchases,Bar Fruit,ml,6 x 1L,8.000,7,157.76,19.72
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,SUNPRIDE PINEAPPLE - 12 X 1 LIT,58920349,Minerals,Minerals,ml,12 X 1 LIT,4.000,4,67.91,16.98
Botanist Edinburgh,New World Trading Company,Birtwistles Catering Butchers,8OZ CUMBERLAND RING - 4 Pack,SAS301EU0193227,Food Purchase Lines,82 Meat,ph,PH,26.000,9,138.06,5.31
''';

        final result = importer.buildImportPlan(
          csvText: csv,
          ingredients: const [
            Ingredient(
              id: '1',
              name: '42 Below Vodka',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '2',
              name: 'Absolut Vanilla Vodka',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '3',
              name: 'Beefeater Pink Gin',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '4',
              name: 'Maker\'s Mark Bourbon',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '5',
              name: 'Martini Rosso',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '6',
              name: 'Lemon Juice',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '7',
              name: 'Pineapple Juice',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
            Ingredient(
              id: '8',
              name: 'Missing Ingredient',
              bottleSizeMl: 0,
              bottleCost: 0,
            ),
          ],
          recipes: const [
            CocktailRecipe(
              id: 'recipe-1',
              name: 'Test Cocktail',
              category: 'Signature',
              glassware: '',
              garnish: '',
              method: '',
              notes: '',
              ingredients: [
                RecipeIngredient(
                  ingredientName: '42 Below Vodka',
                  measureMl: 40,
                ),
                RecipeIngredient(
                  ingredientName: 'Absolut Vanilla Vodka',
                  measureMl: 25,
                ),
                RecipeIngredient(
                  ingredientName: 'Beefeater Pink Gin',
                  measureMl: 35,
                ),
                RecipeIngredient(
                  ingredientName: 'Maker\'s Mark Bourbon',
                  measureMl: 50,
                ),
                RecipeIngredient(
                  ingredientName: 'Martini Rosso',
                  measureMl: 15,
                ),
                RecipeIngredient(ingredientName: 'Lemon Juice', measureMl: 20),
                RecipeIngredient(
                  ingredientName: 'Pineapple Juice',
                  measureMl: 50,
                ),
                RecipeIngredient(
                  ingredientName: 'Missing Ingredient',
                  measureMl: 10,
                ),
              ],
              sourceLabel: 'test',
              needsReview: false,
              reviewFlags: [],
              isApproved: true,
              wasManuallyReviewed: true,
            ),
          ],
          batches: [],
        );

        expect(result.matchedIngredients, hasLength(7));

        final martiniRosso = result.matchedIngredients.firstWhere(
          (item) => item.ingredient.name == 'Martini Rosso',
        );
        expect(martiniRosso.bottleSizeMl, 750);
        expect(martiniRosso.bottlePrice, closeTo(10.34, 0.001));

        final lemonJuice = result.matchedIngredients.firstWhere(
          (item) => item.ingredient.name == 'Lemon Juice',
        );
        expect(lemonJuice.bottleSizeMl, 1000);
        expect(lemonJuice.bottlePrice, closeTo(19.72 / 6, 0.001));

        final pineappleJuice = result.matchedIngredients.firstWhere(
          (item) => item.ingredient.name == 'Pineapple Juice',
        );
        expect(pineappleJuice.bottleSizeMl, 1000);
        expect(pineappleJuice.bottlePrice, closeTo(16.98 / 12, 0.001));

        expect(result.unmatchedIngredientNames, ['Missing Ingredient']);
      },
    );

    test('supports slight name differences and duplicate spirit aliases', () {
      const csv = '''
Outlet Name,CompanyName,SupplierName,ProductName,ProductReference,Category,Subcategory,Unit,PackSize,UnitQuantity,OrderCount,TotalPrice,AveragePrice
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,BEEFEATER - 70cl Bot,32020047,Spirits,Gin,ml,70cl Bot,36.000,4,513.36,14.26
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,GIFF GOMME 1LTR - Litre,36280147,Liqueurs,Liqueurs,ml,Litre,24.000,4,187.68,7.82
Botanist Edinburgh,New World Trading Company,LWC Drinks - Manchester,THE PICKLE HOUSE SPICED TOMATO (BLOODY M - 20cl,COCKTAIL/PIC1,Liqueurs,Liqueurs,ml,20cl,80.000,2,90.40,1.13
''';

      final result = importer.buildImportPlan(
        csvText: csv,
        ingredients: const [
          Ingredient(
            id: '1',
            name: 'Beefeater Gin',
            bottleSizeMl: 0,
            bottleCost: 0,
          ),
          Ingredient(
            id: '2',
            name: 'Giffard Gomme',
            bottleSizeMl: 0,
            bottleCost: 0,
          ),
          Ingredient(id: '3', name: 'Gomme', bottleSizeMl: 0, bottleCost: 0),
          Ingredient(
            id: '4',
            name: 'Pickle House Bloody Mary Spiced Mix',
            bottleSizeMl: 0,
            bottleCost: 0,
          ),
          Ingredient(
            id: '5',
            name: 'Pickle House Mary Mix',
            bottleSizeMl: 0,
            bottleCost: 0,
          ),
        ],
        recipes: const [
          CocktailRecipe(
            id: 'recipe-1',
            name: 'Test Cocktail',
            category: 'Signature',
            glassware: '',
            garnish: '',
            method: '',
            notes: '',
            ingredients: [
              RecipeIngredient(ingredientName: 'Beefeater Gin', measureMl: 40),
              RecipeIngredient(ingredientName: 'Giffard Gomme', measureMl: 10),
              RecipeIngredient(ingredientName: 'Gomme', measureMl: 10),
              RecipeIngredient(
                ingredientName: 'Pickle House Bloody Mary Spiced Mix',
                measureMl: 100,
              ),
              RecipeIngredient(
                ingredientName: 'Pickle House Mary Mix',
                measureMl: 100,
              ),
            ],
            sourceLabel: 'test',
            needsReview: false,
            reviewFlags: [],
            isApproved: true,
            wasManuallyReviewed: true,
          ),
        ],
        batches: [],
      );

      expect(result.unmatchedIngredientNames, isEmpty);
      expect(result.matchedIngredients, hasLength(5));
      expect(
        result.matchedIngredients
            .where((item) => item.sourceProductName.contains('PICKLE HOUSE'))
            .length,
        2,
      );
      expect(
        result.matchedIngredients
            .where((item) => item.ingredient.name.contains('Gomme'))
            .map((item) => item.bottlePrice)
            .toSet(),
        {7.82},
      );
    });
  });
}
