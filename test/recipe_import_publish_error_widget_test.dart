import 'package:flutter_test/flutter_test.dart';
import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/core/utils/curated_recipe_importer.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('publish failure surfaces and does not silently import', () async {
    final repository = _FailingSaveTrainingRepository();
    final controller = AppController(
      authRepository: _OwnerAuthRepository(),
      trainingRepository: repository,
      environment: _firebaseEnvironment,
    );
    await controller.initialize(usingFirebase: true);
    final initialRecipeCount = repository.recipes.length;

    final plan = await controller.importCuratedSpecs(
      conflictMode: CuratedImportConflictMode.updateExisting,
    );
    final approvedDraft = controller.approveImportDraft(
      plan.importResult.drafts.firstWhere(
        (draft) => draft.name == 'Aperol Spritz',
      ),
    );
    final updatedDrafts = [
      for (final draft in plan.importResult.drafts)
        draft.id == approvedDraft.id ? approvedDraft : draft,
    ];

    await expectLater(
      () => controller.saveImportedDrafts(updatedDrafts),
      throwsException,
    );
    expect(controller.errorMessage, isNotNull);
    expect(repository.saveCallCount, 1);
    expect(repository.recipes.length, initialRecipeCount);
  });
}

const _firebaseEnvironment = AppEnvironment(
  allowOwnerBootstrap: false,
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
  appBuildTimestamp: '2026-05-22T00:00:00Z',
  appVersionLabel: 'test-suite',
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
  Future<void> deleteVenueInvite({
    required String venueId,
    required String inviteId,
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
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FailingSaveTrainingRepository extends LocalTrainingRepository {
  int saveCallCount = 0;

  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    saveCallCount += 1;
    throw Exception('permission denied');
  }
}
