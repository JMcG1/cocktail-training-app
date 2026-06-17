import 'package:stock_variance_coach/core/config/app_environment.dart';
import 'package:stock_variance_coach/data/repositories/demo_repositories.dart';
import 'package:stock_variance_coach/domain/models/models.dart';
import 'package:stock_variance_coach/domain/repositories/repositories.dart';
import 'package:stock_variance_coach/presentation/controllers/app_controller.dart';

AppController buildTestController({AppUser? user}) {
  return AppController(
    authRepository: FakeAuthRepository(currentUser: user),
    trainingRepository: LocalTrainingRepository(),
    environment: const AppEnvironment(
      allowOwnerBootstrap: false,
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

AppUser buildTestUser({required UserRole role, required String name}) {
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

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.currentUser});

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
    currentUser = buildTestUser(role: UserRole.owner, name: displayName);
    return currentUser!;
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    return currentUser ?? buildTestUser(role: UserRole.manager, name: 'Manager');
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
    currentUser = buildTestUser(role: UserRole.bartender, name: displayName);
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
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  }) async {}

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}
