import 'dart:convert';

import 'package:cocktail_training/app/app.dart';
import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/cocktail.dart';
import 'package:cocktail_training/models/ingredient.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/screens/login_screen.dart';
import 'package:cocktail_training/services/invite_service.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionService.instance.signOut();
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
    expect(find.text('Manager'), findsAtLeastNWidgets(1));
  });

  test('staff invite creates staff user and manager invite creates manager user', () async {
    await SessionService.instance.initialize();
    const managerEmail = 'manager@cocktailtraining.app';
    final signInError = await SessionService.instance.signIn(
      email: managerEmail,
      password: 'training123',
    );
    expect(signInError, isNull);

    final manager = SessionService.instance.currentUser!;
    final inviteService = InviteService.instance;

    final staffInvite = await inviteService.createInvite(
      manager: manager,
      role: UserRole.staff,
      maxUses: 1,
      expiryDays: 30,
    );
    final managerInvite = await inviteService.createInvite(
      manager: manager,
      role: UserRole.manager,
      maxUses: 1,
      expiryDays: 30,
    );

    final staffResult = await SessionService.instance.joinWithInvite(
      name: 'Staff Member',
      email: 'staff.member@example.com',
      password: 'secret123',
      invite: staffInvite,
    );
    expect(staffResult.isSuccess, isTrue);
    expect(staffResult.user?.role, UserRole.staff);

    final managerResult = await SessionService.instance.joinWithInvite(
      name: 'Second Manager',
      email: 'second.manager@example.com',
      password: 'secret123',
      invite: managerInvite,
    );
    expect(managerResult.isSuccess, isTrue);
    expect(managerResult.user?.role, UserRole.manager);
  });

  test('invalid invite fails safely', () async {
    await SessionService.instance.initialize();
    final result = await InviteService.instance.validateToken('NOTREAL');

    expect(result.isValid, isFalse);
    expect(result.error, contains('does not exist'));
  });

  testWidgets('staff cannot open manager dashboard route', (tester) async {
    SharedPreferences.setMockInitialValues(_mockStoreForStaffSession());

    await tester.pumpWidget(const CocktailTrainingApp());
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsWidgets);

    final context = tester.element(find.text('Library').first);
    Navigator.of(context).pushNamed('/manager');
    await tester.pumpAndSettle();

    expect(find.text('Manager Dashboard'), findsNothing);
    expect(find.text('Find specs fast'), findsOneWidget);
    expect(find.text('Manager access required for that screen.'), findsOneWidget);
  });

  testWidgets('forgot password validates empty and invalid emails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Send reset link'));
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your work email.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

}

Map<String, Object> _mockStoreForStaffSession() {
  const venueId = 'venue-demo-lab';
  final now = DateTime(2026, 4, 26).millisecondsSinceEpoch;

  return {
    'app_seeded_v1': true,
    'app_session_user_id_v1': 'staff-1',
    'app_users_v1': jsonEncode([
      {
        'id': 'staff-1',
        'name': 'Taylor',
        'email': 'taylor@example.com',
        'password': 'secret123',
        'role': 'staff',
        'venueId': venueId,
        'active': true,
        'createdAtMillis': now,
        'lastSignInAtMillis': now,
      },
    ]),
    'app_venues_v1': jsonEncode([
      {
        'id': venueId,
        'name': 'Cocktail Training Lab',
        'createdBy': 'manager-demo',
        'createdAtMillis': now,
      },
    ]),
    'app_invites_v1': jsonEncode([]),
  };
}
