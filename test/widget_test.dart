import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  testWidgets('landing screen shows Cocktail Training login flow', (tester) async {
    final controller = _buildController();
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(
        home: LandingScreen(controller: controller, onOpenTraining: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cocktail Training'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Forgot password? Send reset link'), findsOneWidget);
    expect(find.text('Approved learning library'), findsOneWidget);
  });

  testWidgets('bartender library shows approved cocktails only', (tester) async {
    final controller = _buildController(
      user: _user(role: UserRole.bartender, name: 'Bartender'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CocktailLibraryTab(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approved cocktail library'), findsOneWidget);
    expect(find.text('Aperol Spritz'), findsWidgets);
  });

  testWidgets('study mode reveals approved spec details', (tester) async {
    final controller = _buildController(
      user: _user(role: UserRole.bartender, name: 'Bartender'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StudyModeTab(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Study mode'), findsOneWidget);
    expect(find.text('Reveal ingredients'), findsOneWidget);

    await tester.tap(find.text('Reveal ingredients'));
    await tester.pumpAndSettle();

    expect(find.text('Ingredients'), findsOneWidget);
  });

  testWidgets('manager workspace keeps team tools and invites', (tester) async {
    final controller = _buildController(
      user: _user(role: UserRole.manager, name: 'Manager'),
    );
    await controller.initialize(usingFirebase: false);

    await tester.pumpWidget(
      MaterialApp(home: ManagerWorkspace(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cocktail Training · Library'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Study'), findsWidgets);
    expect(find.text('Quiz'), findsWidgets);
    expect(find.text('Progress'), findsWidgets);
    expect(find.text('Team'), findsWidgets);
  });

  test('practice quiz can be generated and submitted from approved data', () async {
    final controller = _buildController(
      user: _user(role: UserRole.bartender, name: 'Bartender'),
    );
    await controller.initialize(usingFirebase: false);

    final session = controller.generatePracticeQuiz(bartenderName: 'Bartender');
    expect(session.questions, isNotEmpty);

    final answers = {
      for (final question in session.questions) question.id: question.correctAnswer,
    };
    final attempt = controller.submitQuizAttempt(
      sessionId: session.id,
      bartenderName: 'Bartender',
      answers: answers,
    );

    expect(attempt.scorePercent, greaterThanOrEqualTo(0));
    expect(controller.latestAttempt, isNotNull);
  });

  test('invite route parser supports path and query formats', () {
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
}

AppController _buildController({AppUser? user}) {
  return AppController(
    authRepository: _FakeAuthRepository(currentUser: user),
    trainingRepository: LocalTrainingRepository(),
    environment: const AppEnvironment(
      firebaseApiKey: '',
      firebaseAppId: '',
      firebaseMessagingSenderId: '',
      firebaseProjectId: '',
      firebaseAuthDomain: '',
      firebaseStorageBucket: '',
      demoManagerEmail: 'demo@example.com',
      demoManagerPassword: 'password',
      defaultVenueId: 'venue-1',
      appBuildLabel: 'test-build',
      appBuildTimestamp: '2026-05-25T00:00:00Z',
      appVersionLabel: 'test-suite',
      appMode: AppMode.demo,
    ),
  );
}

AppUser _user({required UserRole role, required String name}) {
  return AppUser(
    id: '${role.name}-1',
    email: '${role.name}@example.com',
    displayName: name,
    role: role,
    venueId: 'venue-1',
    venueName: 'Venue One',
    createdAt: DateTime(2026, 1, 1),
    active: true,
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.currentUser});

  @override
  AppUser? currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    currentUser = _user(role: UserRole.owner, name: displayName);
    return currentUser!;
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    return currentUser ?? _user(role: UserRole.manager, name: 'Manager');
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
    return VenueInvite(
      id: 'invite-1',
      venueId: venueId,
      role: role,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      maxUses: maxUses,
      currentUses: 0,
      disabled: false,
    );
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
    return VenueInvite(
      id: inviteId,
      venueId: venueId,
      role: UserRole.bartender,
      createdBy: 'manager-1',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      maxUses: 1,
      currentUses: 0,
      disabled: false,
    );
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
    currentUser = _user(role: UserRole.bartender, name: displayName);
    return currentUser!;
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
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}
