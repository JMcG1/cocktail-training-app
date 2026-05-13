import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/app.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  testWidgets('shows manager sign in entry point', (tester) async {
    await tester.pumpWidget(const StockVarianceCoachRoot());
    await tester.pumpAndSettle();

    expect(find.text('Manager sign-in'), findsOneWidget);
    expect(find.text('Training mode for bartenders'), findsOneWidget);
  });

  testWidgets('production-style landing hides demo credentials', (tester) async {
    final controller = AppController(
      authRepository: _FakeAuthRepository(),
      trainingRepository: LocalTrainingRepository(),
      environment: const AppEnvironment(
        firebaseApiKey: 'key',
        firebaseAppId: 'app',
        firebaseMessagingSenderId: 'sender',
        firebaseProjectId: 'project',
        firebaseAuthDomain: 'project.firebaseapp.com',
        firebaseStorageBucket: 'bucket',
        demoManagerEmail: 'demo@example.com',
        demoManagerPassword: 'password',
        defaultVenueId: 'venue-1',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    await tester.pumpWidget(
      MaterialApp(
        home: LandingScreen(
          controller: controller,
          onOpenTraining: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo email:'), findsNothing);
  });

  testWidgets('firebase manager empty state guides first library step', (tester) async {
    final controller = AppController(
      authRepository: _FakeAuthRepository(
        currentUser: AppUser(
          id: 'manager-1',
          email: 'manager@example.com',
          displayName: 'Manager',
          role: UserRole.manager,
          venueId: 'venue-1',
          venueName: 'Venue One',
          createdAt: DateTime(2026, 1, 1),
          active: true,
        ),
      ),
      trainingRepository: LocalTrainingRepository(),
      environment: const AppEnvironment(
        firebaseApiKey: 'key',
        firebaseAppId: 'app',
        firebaseMessagingSenderId: 'sender',
        firebaseProjectId: 'project',
        firebaseAuthDomain: 'project.firebaseapp.com',
        firebaseStorageBucket: 'bucket',
        demoManagerEmail: 'demo@example.com',
        demoManagerPassword: 'password',
        defaultVenueId: 'venue-1',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerLibraryTab(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No reviewed cocktails are stored yet'), findsOneWidget);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.currentUser});

  @override
  final AppUser? currentUser;

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    return currentUser!;
  }

  @override
  Future<void> signOut() async {}
}
