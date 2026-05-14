import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/app.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  testWidgets('shows manager sign in entry point', (tester) async {
    await tester.pumpWidget(const StockVarianceCoachRoot());
    await tester.pumpAndSettle();

    expect(find.text('Owner or manager sign-in'), findsOneWidget);
    expect(find.text('Create owner account'), findsNothing);
    expect(find.text('Training mode for bartenders'), findsOneWidget);
  });

  testWidgets(
    'firebase landing stays sign-in only and explains invite access',
    (tester) async {
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
          home: LandingScreen(controller: controller, onOpenTraining: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create owner account'), findsNothing);
      expect(find.textContaining('invite-only'), findsOneWidget);
    },
  );

  test('unauthenticated startup survives public preload failures', () async {
    final controller = AppController(
      authRepository: _FakeAuthRepository(),
      trainingRepository: _ThrowingTrainingRepository(),
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

    expect(controller.currentUser, isNull);
    expect(controller.errorMessage, isNull);
  });

  testWidgets('production-style landing hides demo credentials', (
    tester,
  ) async {
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
        home: LandingScreen(controller: controller, onOpenTraining: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo email:'), findsNothing);
  });

  testWidgets('firebase manager empty state guides first library step', (
    tester,
  ) async {
    final controller = AppController(
      authRepository: _FakeAuthRepository(
        currentUser: AppUser(
          id: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          role: UserRole.owner,
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
        home: Scaffold(body: ManagerLibraryTab(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No reviewed cocktails are stored yet'),
      findsOneWidget,
    );
  });

  testWidgets(
    'curated import approve updates visible state and enables saving',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = LocalTrainingRepository();
      final controller = AppController(
        authRepository: _FakeAuthRepository(
          currentUser: AppUser(
            id: 'owner-1',
            email: 'owner@example.com',
            displayName: 'Owner',
            role: UserRole.owner,
            venueId: 'venue-1',
            venueName: 'Venue One',
            createdAt: DateTime(2026, 1, 1),
            active: true,
          ),
        ),
        trainingRepository: repository,
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
      await controller.importCuratedSpecs(
        conflictMode: CuratedImportConflictMode.importOnlyNew,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecipeImportTab(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      final saveButtonFinder = find.widgetWithText(
        OutlinedButton,
        'Save approved recipes',
      );
      expect(tester.widget<OutlinedButton>(saveButtonFinder).onPressed, isNull);

      final aperolTitle = find.text('Aperol Spritz').first;
      await tester.scrollUntilVisible(
        aperolTitle,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      final aperolCard = find
          .ancestor(of: aperolTitle, matching: find.byType(Card))
          .first;
      final approveButtonFinder = find.descendant(
        of: aperolCard,
        matching: find.widgetWithText(ElevatedButton, 'Approve recipe'),
      );
      await tester.ensureVisible(approveButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(approveButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Approved'), findsWidgets);
      expect(find.textContaining('Approved: 1'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(saveButtonFinder).onPressed,
        isNotNull,
      );

      await tester.ensureVisible(saveButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(repository.recipes, isNotEmpty);
      expect(
        repository.recipes.any((recipe) => recipe.name == 'Aperol Spritz'),
        isTrue,
      );
    },
  );
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
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return currentUser == null ? const [] : [currentUser!];
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _ThrowingTrainingRepository extends LocalTrainingRepository {
  @override
  Future<void> initialize() async {
    throw Exception('firestore public preload failed');
  }
}
