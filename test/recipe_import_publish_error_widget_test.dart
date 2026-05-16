import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';
import 'package:stock_variance_coach/presentation/screens/app_shell.dart';

void main() {
  testWidgets('publish failure stays visible and does not silently import', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FailingSaveTrainingRepository();
    final controller = AppController(
      authRepository: _OwnerAuthRepository(),
      trainingRepository: repository,
      environment: _firebaseEnvironment,
    );
    await controller.initialize(usingFirebase: true);
    await controller.importCuratedSpecs(
      conflictMode: CuratedImportConflictMode.importOnlyNew,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecipeImportTab(controller: controller))),
    );
    await tester.pumpAndSettle();

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

    final saveButtonFinder = find.widgetWithText(
      OutlinedButton,
      'Publish approved specs',
    );
    await tester.ensureVisible(saveButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(saveButtonFinder);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('We could not publish the approved specs because'),
      findsWidgets,
    );
    expect(repository.recipes, isEmpty);
  });
}

const _firebaseEnvironment = AppEnvironment(
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
);

class _OwnerAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => AppUser(
    id: 'owner-1',
    email: 'owner@example.com',
    displayName: 'Owner',
    role: UserRole.owner,
    venueId: 'venue-1',
    venueName: 'Venue One',
    createdAt: DateTime(2026, 1, 1),
    active: true,
  );

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
    return [currentUser!];
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

class _FailingSaveTrainingRepository extends LocalTrainingRepository {
  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    throw Exception('permission denied');
  }
}
