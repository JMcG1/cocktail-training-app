import 'package:cocktail_training/app/app.dart';
import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/ingredient.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bottom navigation switches between training tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingShell(
          currentUser: const AppUser(
            id: 'staff-1',
            name: 'Taylor',
            email: 'taylor@example.com',
            password: 'secret123',
            role: UserRole.staff,
            venueId: 'venue-1',
            active: true,
            createdAtMillis: 1,
          ),
          cocktails: [
            Cocktail(
              id: 'espresso-martini',
              name: 'Espresso Martini',
              category: 'Cocktails',
              buildStyle: 'Shaken-Drink',
              glassware: 'Coupe glass',
              garnish: '3 coffee beans',
              description: 'Coffee-led vodka cocktail.',
              source: 'Unit test',
              sourcePage: 1,
              tags: const ['Cocktails', 'Shaken Drink'],
              ingredients: const [
                Ingredient(name: 'Vodka', measure: '50ml'),
                Ingredient(name: 'Espresso', measure: '25ml'),
              ],
              methodSteps: const [
                'Shake with ice',
                'Double strain into a coupe',
              ],
              notes: const [],
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Study mode'), findsNothing);
    expect(find.text('Quiz mode'), findsNothing);

    await tester.tap(find.text('Study').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Study mode'), findsWidgets);

    await tester.tap(find.text('Quiz').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Quiz mode'), findsWidgets);

    await tester.tap(find.text('Library').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Find specs fast'), findsOneWidget);
  });

  testWidgets('manager tab only appears for managers', (tester) async {
    Future<void> pumpShell(String role) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingShell(
            key: ValueKey(role),
            currentUser: AppUser(
              id: 'user-$role',
              name: 'Morgan',
              email: 'morgan@example.com',
              password: 'secret123',
              role: role == 'manager' ? UserRole.manager : UserRole.staff,
              venueId: 'venue-1',
              active: true,
              createdAtMillis: 1,
            ),
            cocktails: const [],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpShell('bartender');
    expect(find.text('Manager'), findsNothing);

    await pumpShell('manager');
    expect(find.text('Manager'), findsOneWidget);
  });
}
