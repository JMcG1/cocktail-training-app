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

    expect(find.text('Welcome back to service support'), findsOneWidget);
    expect(find.text('Create owner account'), findsNothing);
    expect(find.text('Bartender practice space'), findsOneWidget);
    expect(find.textContaining('Build '), findsOneWidget);
    expect(find.text('Refresh app'), findsOneWidget);
    expect(find.text('Clear saved app data'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
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
          appBuildLabel: 'test-build',
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
      expect(find.text('Open practice space'), findsNothing);
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
        appBuildLabel: 'test-build',
        appMode: AppMode.firebase,
      ),
    );

    await controller.initialize(usingFirebase: true);

    expect(controller.currentUser, isNull);
    expect(controller.errorMessage, isNull);
  });

  test('owner can generate and submit a practice quiz', () async {
    final repository = LocalTrainingRepository();
    repository.saveImportedDrafts([
      RecipeImportDraft(
        id: 'owner-quiz-1',
        sourceLabel: 'test',
        pageLabel: '1',
        name: 'Owner Daiquiri',
        category: 'Classics',
        glassware: 'Coupe',
        garnish: 'Lime wheel',
        method: 'Shake',
        notes: '',
        ingredients: const [
          RecipeIngredient(ingredientName: 'Rum', measureMl: 50),
          RecipeIngredient(ingredientName: 'Lime', measureMl: 25),
        ],
        reviewFlags: const [],
        status: RecipeDraftStatus.approved,
        wasManuallyReviewed: true,
      ),
    ]);
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
        appBuildLabel: 'test-build',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    final session = controller.generatePracticeQuiz(bartenderName: 'Owner');
    expect(session.questions, isNotEmpty);

    final answers = {
      for (final question in session.questions) question.id: question.correctAnswer,
    };
    final attempt = controller.submitQuizAttempt(
      sessionId: session.id,
      bartenderName: 'Owner',
      answers: answers,
    );

    expect(attempt.scorePercent, greaterThanOrEqualTo(0));
    expect(controller.latestAttempt, isNotNull);
  });

  test('invite route parser accepts path and query variants', () {
    final pathInvite = inviteRouteFromUri(
      Uri.parse('https://example.com/join/venue-1/invite-1'),
    );
    final queryInvite = inviteRouteFromUri(
      Uri.parse('https://example.com/?venue=venue-2&invite=invite-2'),
    );

    expect(pathInvite, isNotNull);
    expect(pathInvite!.venueId, 'venue-1');
    expect(pathInvite.inviteId, 'invite-1');
    expect(queryInvite, isNotNull);
    expect(queryInvite!.venueId, 'venue-2');
    expect(queryInvite.inviteId, 'invite-2');
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
        appBuildLabel: 'test-build',
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
        appBuildLabel: 'test-build',
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
      find.textContaining('No cocktails are live yet'),
      findsOneWidget,
    );
  });

  testWidgets('owner settings expose diagnostics and cocktail-list status', (
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
        appBuildLabel: 'test-build',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(controller: controller, isOnline: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Admin diagnostics'), findsOneWidget);
    expect(find.text('Cocktail list'), findsOneWidget);
    expect(find.text('Venue ID'), findsOneWidget);
    expect(find.text('Live cocktails'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
  });

  testWidgets('owner workspace includes bartender learning tools', (
    tester,
  ) async {
    final repository = LocalTrainingRepository();
    repository.saveImportedDrafts([
      RecipeImportDraft(
        id: 'recipe-owner-1',
        sourceLabel: 'test',
        pageLabel: '1',
        name: 'Owner Negroni',
        category: 'Classics',
        glassware: 'Rocks',
        garnish: 'Orange twist',
        method: 'Stir',
        notes: '',
        ingredients: const [
          RecipeIngredient(ingredientName: 'Gin', measureMl: 25),
          RecipeIngredient(ingredientName: 'Campari', measureMl: 25),
          RecipeIngredient(ingredientName: 'Vermouth', measureMl: 25),
        ],
        reviewFlags: const [],
        status: RecipeDraftStatus.approved,
        wasManuallyReviewed: true,
      ),
    ]);
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
        appBuildLabel: 'test-build',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    await tester.pumpWidget(
      MaterialApp(home: ManagerWorkspace(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cocktail list'), findsWidgets);
    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Refreshers'), findsOneWidget);

    await tester.tap(find.text('Study').last);
    await tester.pumpAndSettle();
    expect(find.text('Study mode'), findsOneWidget);

    await tester.tap(find.text('Practice').last);
    await tester.pumpAndSettle();
    expect(find.text('Start a practice round'), findsOneWidget);

    await tester.tap(find.text('Start practice round'));
    await tester.pumpAndSettle();
    expect(find.text('Practice round'), findsOneWidget);
  });

  testWidgets('bartender library cards offer learn and quiz actions', (
    tester,
  ) async {
    final repository = LocalTrainingRepository();
    repository.saveImportedDrafts([
      RecipeImportDraft(
        id: 'recipe-1',
        sourceLabel: 'test',
        pageLabel: '1',
        name: 'Clover Club',
        category: 'Signature',
        glassware: 'Coupe',
        garnish: 'Raspberry',
        method: 'Shake',
        notes: 'Dry shake first.',
        ingredients: const [
          RecipeIngredient(ingredientName: 'Gin', measureMl: 50),
          RecipeIngredient(ingredientName: 'Lemon', measureMl: 25),
        ],
        reviewFlags: const [],
        status: RecipeDraftStatus.approved,
        wasManuallyReviewed: true,
      ),
    ]);
    final controller = AppController(
      authRepository: _FakeAuthRepository(
        currentUser: AppUser(
          id: 'bartender-1',
          email: 'bartender@example.com',
          displayName: 'Bartender',
          role: UserRole.bartender,
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
        appBuildLabel: 'test-build',
        appMode: AppMode.firebase,
      ),
    );
    await controller.initialize(usingFirebase: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CocktailLibraryTab(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Learn'), findsOneWidget);
    expect(find.text('Quiz me'), findsOneWidget);
    expect(find.text('Clover Club'), findsWidgets);
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
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<VenueInvite>> listVenueInvites({required String venueId}) async {
    return const [];
  }

  @override
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    return null;
  }

  @override
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  }) async {}

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
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
