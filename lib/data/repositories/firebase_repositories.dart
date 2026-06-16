import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_environment.dart';
import '../../core/utils/approved_cocktail_prices.dart';
import '../../core/utils/batch_recipe_graph.dart';
import '../../core/utils/curated_recipe_importer.dart';
import '../../core/utils/legacy_recipe_ids.dart';
import '../../core/utils/pdf_recipe_extractor.dart';
import '../../core/utils/recipe_text_parser.dart';
import '../../core/utils/variance_math.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/firestore_serializers.dart';
import 'demo_repositories.dart';

class FirebaseManagerAuthRepository implements AuthRepository {
  FirebaseManagerAuthRepository({required this.environment});

  final AppEnvironment environment;
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {
    final auth = firebase_auth.FirebaseAuth.instance;
    developer.log(
      'Firebase auth initialize start currentUser=${auth.currentUser?.uid ?? '<none>'}',
      name: 'FirebaseAuthStartup',
    );
    firebase_auth.User? user;
    try {
      user = await auth.authStateChanges().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => auth.currentUser,
      );
    } catch (_) {
      user = auth.currentUser;
    }
    if (user == null) {
      _currentUser = null;
      developer.log(
        'Firebase auth initialize complete signedOut',
        name: 'FirebaseAuthStartup',
      );
      return;
    }
    _currentUser = await _buildUser(user);
    if (_currentUser != null && !_currentUser!.active) {
      await auth.signOut();
      _currentUser = null;
      developer.log(
        'Firebase auth initialize signed out inactive user uid=${user.uid}',
        name: 'FirebaseAuthStartup',
        level: 900,
      );
      return;
    }
    developer.log(
      'Firebase auth initialize complete uid=${user.uid} venue=${_currentUser?.venueId ?? '<unknown>'} role=${_currentUser?.role.name ?? '<unknown>'}',
      name: 'FirebaseAuthStartup',
    );
  }

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    if (firebase_auth.FirebaseAuth.instance.currentUser != null) {
      throw Exception(
        'Sign out of the current account before creating a bootstrap owner account.',
      );
    }
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = displayName.trim();
    final normalizedVenueName = venueName.trim();
    FirebaseApp? isolatedApp;
    firebase_auth.FirebaseAuth? isolatedAuth;
    firebase_auth.User? isolatedUser;
    var bootstrapCommitted = false;
    _logInviteEvent(
      'Bootstrap owner creation requested email=$normalizedEmail',
    );
    try {
      isolatedApp = await _createIsolatedInviteApp();
      isolatedAuth = firebase_auth.FirebaseAuth.instanceFor(app: isolatedApp);
      isolatedUser = await _createOrRecoverBootstrapUser(
        auth: isolatedAuth,
        email: normalizedEmail,
        password: password,
      );
      await isolatedUser.updateDisplayName(normalizedName);
      final bootstrapResult = await _consumeBootstrapGrantAndCreateOwner(
        firestore: FirebaseFirestore.instanceFor(app: isolatedApp),
        userId: isolatedUser.uid,
        email: normalizedEmail,
        displayName: normalizedName,
        venueName: normalizedVenueName,
      );
      bootstrapCommitted = true;
      _logInviteEvent(
        'Bootstrap owner creation committed venue=${bootstrapResult.venueId} email=$normalizedEmail uid=${isolatedUser.uid}',
        level: 900,
      );
      await isolatedAuth.signOut();
      await isolatedApp.delete();
      isolatedAuth = null;
      isolatedApp = null;

      final credential = await firebase_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
      final signedInUser = credential.user;
      if (signedInUser == null) {
        throw Exception(
          'Your owner account is ready, but sign-in did not finish just now. Please sign in with the same email and password to continue.',
        );
      }
      _currentUser = await _buildUser(signedInUser);
      return _currentUser!;
    } catch (error, stackTrace) {
      _logInviteEvent(
        'Bootstrap owner creation failed email=$normalizedEmail error=$error',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (!bootstrapCommitted && isolatedUser != null && isolatedAuth != null) {
        final rollbackDeleted = await _rollbackInviteUser(
          auth: isolatedAuth,
          user: isolatedUser,
          venueId: 'bootstrap-pending',
          inviteId: 'bootstrap-grant',
        );
        if (!rollbackDeleted) {
          _logInviteEvent(
            'Bootstrap rollback left an orphan auth account email=$normalizedEmail uid=${isolatedUser.uid}',
            level: 1000,
          );
        }
      }
      try {
        await isolatedAuth?.signOut();
      } catch (_) {}
      if (isolatedApp != null) {
        try {
          await isolatedApp.delete();
        } catch (_) {}
      }
      try {
        await firebase_auth.FirebaseAuth.instance.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    final credential = await firebase_auth.FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to sign in.');
    }
    _currentUser = await _buildUser(user);
    if (!_currentUser!.active) {
      await signOut();
      throw Exception(
        'This account is currently paused. Ask the owner/admin to restore access when you are ready.',
      );
    }
    return _currentUser!;
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw Exception(
      'Direct manager account creation has been replaced by invite-only join links.',
    );
  }

  @override
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    _logInviteEvent(
      'Invite creation requested venue=$venueId role=${role.name} maxUses=$maxUses',
    );
    if (role == UserRole.owner) {
      _logInviteEvent(
        'Invite creation rejected venue=$venueId reason=owner_role_requested',
        level: 900,
      );
      throw Exception(
        'Owner/admin access is issued separately and cannot be created from venue invites.',
      );
    }
    final doc = FirebaseFirestore.instance
        .collection(FirestorePaths.invites(venueId))
        .doc();
    final invite = VenueInvite(
      id: doc.id,
      venueId: venueId,
      role: role,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      maxUses: maxUses,
      currentUses: 0,
      disabled: false,
    );
    await doc.set(FirestoreSerializers.venueInviteToMap(invite));
    _logInviteEvent(
      'Invite created venue=$venueId invite=${invite.id} role=${role.name} maxUses=$maxUses expiresAt=${invite.expiresAt.toIso8601String()}',
    );
    return invite;
  }

  @override
  Future<List<VenueInvite>> listVenueInvites({required String venueId}) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(FirestorePaths.invites(venueId))
        .get();
    final invites = snapshot.docs
        .map(
          (doc) => FirestoreSerializers.venueInviteFromMap(doc.id, doc.data()),
        )
        .toList();
    invites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return invites;
  }

  @override
  Future<VenueInvite?> fetchVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection(FirestorePaths.invites(venueId))
        .doc(inviteId)
        .get();
    if (!doc.exists) {
      return null;
    }
    return FirestoreSerializers.venueInviteFromMap(inviteId, doc.data()!);
  }

  @override
  Future<void> setVenueInviteDisabled({
    required String venueId,
    required String inviteId,
    required bool disabled,
  }) async {
    _logInviteEvent(
      'Invite status change requested venue=$venueId invite=$inviteId disabled=$disabled',
    );
    await FirebaseFirestore.instance
        .collection(FirestorePaths.invites(venueId))
        .doc(inviteId)
        .update({'disabled': disabled});
    _logInviteEvent(
      'Invite status changed venue=$venueId invite=$inviteId disabled=$disabled',
    );
  }

  @override
  Future<void> deleteVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    _logInviteEvent('Invite delete requested venue=$venueId invite=$inviteId');
    await FirebaseFirestore.instance
        .collection(FirestorePaths.invites(venueId))
        .doc(inviteId)
        .delete();
    _logInviteEvent('Invite deleted venue=$venueId invite=$inviteId');
  }

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (firebase_auth.FirebaseAuth.instance.currentUser != null) {
      _logInviteEvent(
        'Invite redemption rejected venue=$venueId invite=$inviteId reason=primary_session_active',
        level: 900,
      );
      throw Exception(
        'Sign out of the current account before joining a venue from an invite link.',
      );
    }
    final normalizedEmail = email.trim();
    final normalizedName = displayName.trim();
    FirebaseApp? isolatedApp;
    firebase_auth.FirebaseAuth? isolatedAuth;
    FirebaseFirestore? isolatedFirestore;
    firebase_auth.User? isolatedUser;
    var transactionCommitted = false;
    _logInviteEvent(
      'Invite redemption requested venue=$venueId invite=$inviteId email=$normalizedEmail',
    );
    try {
      isolatedApp = await _createIsolatedInviteApp();
      isolatedAuth = firebase_auth.FirebaseAuth.instanceFor(app: isolatedApp);
      isolatedFirestore = FirebaseFirestore.instanceFor(app: isolatedApp);

      isolatedUser = await _createOrRecoverInviteUser(
        auth: isolatedAuth,
        email: normalizedEmail,
        password: password,
      );
      await isolatedUser.updateDisplayName(normalizedName);
      final existingAssignment = await _loadExistingInviteAssignment(
        firestore: isolatedFirestore,
        userId: isolatedUser.uid,
      );
      if (existingAssignment != null) {
        if (existingAssignment.venueId == venueId &&
            existingAssignment.inviteId == inviteId &&
            existingAssignment.role != UserRole.owner) {
          transactionCommitted = true;
          _logInviteEvent(
            'Invite redemption resumed using existing linked user doc venue=$venueId invite=$inviteId uid=${isolatedUser.uid}',
            level: 900,
          );
        } else {
          _logInviteEvent(
            'Invite redemption rejected venue=$venueId invite=$inviteId reason=existing_assignment_conflict uid=${isolatedUser.uid}',
            level: 1000,
          );
          throw Exception(
            'This email is already linked to a venue account. Sign in instead, or ask your venue manager for help if you expected to join a different venue.',
          );
        }
      }

      if (!transactionCommitted) {
        final redemption = await _redeemInviteInFirestore(
          firestore: isolatedFirestore,
          venueId: venueId,
          inviteId: inviteId,
          userId: isolatedUser.uid,
          email: normalizedEmail,
          displayName: normalizedName,
        );
        transactionCommitted = true;
        _logInviteEvent(
          'Invite redemption committed venue=${redemption.invite.venueId} invite=${redemption.invite.id} role=${redemption.invite.role.name} venueName=${redemption.venueName}',
          level: 900,
        );
      }

      await isolatedAuth.signOut();
      await isolatedApp.delete();
      isolatedAuth = null;
      isolatedApp = null;

      final credential = await firebase_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
      final signedInUser = credential.user;
      if (signedInUser == null) {
        _logInviteEvent(
          'Invite redemption committed but primary sign-in returned null venue=$venueId invite=$inviteId uid=${isolatedUser.uid}',
          level: 1000,
        );
        throw Exception(
          'Your venue access is ready, but sign-in did not finish just now. Please sign in with the same email and password to continue.',
        );
      }
      _currentUser = await _buildUser(signedInUser);
      _logInviteEvent(
        'Invite redemption completed venue=$venueId invite=$inviteId uid=${signedInUser.uid} role=${_currentUser!.role.name}',
      );
      return _currentUser!;
    } catch (error, stackTrace) {
      _logInviteEvent(
        'Invite redemption failed venue=$venueId invite=$inviteId email=$normalizedEmail error=$error',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (!transactionCommitted &&
          isolatedUser != null &&
          isolatedAuth != null) {
        final rollbackDeleted = await _rollbackInviteUser(
          auth: isolatedAuth,
          user: isolatedUser,
          venueId: venueId,
          inviteId: inviteId,
        );
        if (!rollbackDeleted) {
          _logInviteEvent(
            'Invite rollback left an orphan auth account venue=$venueId invite=$inviteId uid=${isolatedUser.uid}',
            level: 1000,
          );
        }
      }
      try {
        await isolatedAuth?.signOut();
      } catch (_) {}
      if (isolatedApp != null) {
        try {
          await isolatedApp.delete();
        } catch (_) {}
      }
      try {
        await firebase_auth.FirebaseAuth.instance.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(FirestorePaths.users())
        .where('venueId', isEqualTo: venueId)
        .get();
    final users = await Future.wait(
      snapshot.docs.map(
        (doc) => _buildUserFromDocument(
          id: doc.id,
          emailFallback: doc.data()['email'] as String? ?? '',
          data: doc.data(),
        ),
      ),
    );
    users.sort((a, b) {
      final roleOrder = _roleSortIndex(
        a.role,
      ).compareTo(_roleSortIndex(b.role));
      if (roleOrder != 0) {
        return roleOrder;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return users;
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {
    await FirebaseFirestore.instance
        .collection(FirestorePaths.users())
        .doc(userId)
        .update({'active': active, 'venueId': venueId});
  }

  @override
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  }) async {
    await FirebaseFirestore.instance
        .collection(FirestorePaths.users())
        .doc(userId)
        .update({'active': false, 'venueId': venueId});
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    await firebase_auth.FirebaseAuth.instance.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  @override
  Future<void> signOut() async {
    await firebase_auth.FirebaseAuth.instance.signOut();
    _currentUser = null;
  }

  Future<AppUser> _buildUser(firebase_auth.User user) async {
    developer.log(
      'Loading Firebase user profile uid=${user.uid}',
      name: 'FirebaseAuthStartup',
    );
    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirestorePaths.users())
          .doc(user.uid)
          .get();
      final profile = await _buildUserFromDocument(
        id: user.uid,
        emailFallback: user.email ?? '',
        data: doc.data() ?? const <String, dynamic>{},
        displayNameFallback: user.displayName,
      );
      developer.log(
        'Firebase user profile loaded uid=${user.uid} venue=${profile.venueId} role=${profile.role.name}',
        name: 'FirebaseAuthStartup',
      );
      return profile;
    } on FirebaseException catch (error, stackTrace) {
      developer.log(
        'Firebase user profile load failed uid=${user.uid}',
        name: 'FirebaseAuthStartup',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Your account is set up, but your team access could not be loaded.',
      );
    }
  }

  Future<AppUser> _buildUserFromDocument({
    required String id,
    required String emailFallback,
    required Map<String, dynamic> data,
    String? displayNameFallback,
  }) async {
    final venueId = (data['venueId'] as String? ?? '').trim();
    if (venueId.isEmpty) {
      throw Exception(
        'This account is missing a venue assignment. Ask the owner/admin to restore access.',
      );
    }
    final roleString = (data['role'] as String? ?? '').toLowerCase().trim();
    final role = switch (roleString) {
      'owner' => UserRole.owner,
      'manager' => UserRole.manager,
      'bartender' => UserRole.bartender,
      _ => throw Exception(
        'This account has an unknown role. Ask the owner/admin to restore access.',
      ),
    };
    developer.log(
      'Loading venue profile venue=$venueId for uid=$id',
      name: 'FirebaseAuthStartup',
    );
    final venueDoc = await FirebaseFirestore.instance
        .collection('venues')
        .doc(venueId)
        .get();
    final venueData = venueDoc.data() ?? const <String, dynamic>{};
    final storedDisplayName = _firstNonEmptyString(
      data['displayName'],
      data['name'],
      displayNameFallback,
    );
    return AppUser(
      id: id,
      email: data['email'] as String? ?? emailFallback,
      displayName: storedDisplayName ?? 'Venue teammate',
      role: role,
      venueId: venueId,
      venueName: venueData['name'] as String? ?? 'Venue',
      createdAt: _dateTimeFromUserDocumentValue(data['createdAt']),
      active: data['active'] as bool? ?? true,
    );
  }

  String? _firstNonEmptyString(Object? first, [Object? second, Object? third]) {
    for (final value in [first, second, third]) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  DateTime _dateTimeFromUserDocumentValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  int _roleSortIndex(UserRole role) {
    return switch (role) {
      UserRole.owner => 0,
      UserRole.manager => 1,
      UserRole.bartender => 2,
    };
  }

  FirebaseOptions _firebaseOptions() {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.app().options;
    }
    return FirebaseOptions(
      apiKey: environment.firebaseApiKey,
      appId: environment.firebaseAppId,
      messagingSenderId: environment.firebaseMessagingSenderId,
      projectId: environment.firebaseProjectId,
      authDomain: environment.firebaseAuthDomain.isEmpty
          ? null
          : environment.firebaseAuthDomain,
      storageBucket: environment.firebaseStorageBucket.isEmpty
          ? null
          : environment.firebaseStorageBucket,
    );
  }

  Future<FirebaseApp> _createIsolatedInviteApp() {
    final appName = 'invite-redeem-${DateTime.now().microsecondsSinceEpoch}';
    return Firebase.initializeApp(name: appName, options: _firebaseOptions());
  }

  Future<firebase_auth.User> _createOrRecoverInviteUser({
    required firebase_auth.FirebaseAuth auth,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to create the invited account.');
      }
      _logInviteEvent(
        'Invite auth account created email=$email uid=${user.uid}',
      );
      return user;
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') {
        rethrow;
      }
      _logInviteEvent(
        'Invite auth account already existed for email=$email. Attempting safe recovery.',
        level: 900,
      );
      try {
        final credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;
        if (user == null) {
          throw Exception('Unable to recover the existing invited account.');
        }
        _logInviteEvent(
          'Recovered existing auth account for invite email=$email uid=${user.uid}',
          level: 900,
        );
        return user;
      } on firebase_auth.FirebaseAuthException {
        throw Exception(
          'This email is already registered. Sign in instead, or ask your venue manager for help if an earlier invite attempt did not finish cleanly.',
        );
      }
    }
  }

  Future<firebase_auth.User> _createOrRecoverBootstrapUser({
    required firebase_auth.FirebaseAuth auth,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to create the owner account.');
      }
      _logInviteEvent(
        'Bootstrap auth account created email=$email uid=${user.uid}',
      );
      return user;
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') {
        rethrow;
      }
      _logInviteEvent(
        'Bootstrap auth account already existed for email=$email. Attempting safe recovery.',
        level: 900,
      );
      try {
        final credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;
        if (user == null) {
          throw Exception('Unable to recover the existing owner account.');
        }
        return user;
      } on firebase_auth.FirebaseAuthException {
        throw Exception(
          'This email is already registered. Sign in instead, or ask an existing owner/admin to issue a fresh bootstrap grant if setup did not finish cleanly.',
        );
      }
    }
  }

  Future<_BootstrapOwnerResult> _consumeBootstrapGrantAndCreateOwner({
    required FirebaseFirestore firestore,
    required String userId,
    required String email,
    required String displayName,
    required String venueName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final grantRef = firestore
        .collection(FirestorePaths.bootstrapGrants())
        .doc(normalizedEmail);
    final venueRef = firestore.collection('venues').doc();
    final userRef = firestore.collection(FirestorePaths.users()).doc(userId);
    late DateTime createdAt;
    await firestore.runTransaction((transaction) async {
      final grantSnapshot = await transaction.get(grantRef);
      if (!grantSnapshot.exists) {
        throw Exception(
          'Owner bootstrap is locked down. Ask an existing owner/admin to create a bootstrap grant for this email before trying again.',
        );
      }
      final grantData = grantSnapshot.data() ?? const <String, dynamic>{};
      final disabled = grantData['disabled'] as bool? ?? false;
      final allowedRole = (grantData['role'] as String? ?? '').trim();
      final grantEmail = (grantData['email'] as String? ?? normalizedEmail)
          .trim()
          .toLowerCase();
      final expiresAt = grantData['expiresAt'];
      final alreadyUsed = grantData['usedAt'] != null;
      if (disabled || alreadyUsed) {
        throw Exception(
          'This owner bootstrap grant is no longer active. Ask an existing owner/admin for a fresh grant.',
        );
      }
      if (allowedRole.isNotEmpty && allowedRole != UserRole.owner.name) {
        throw Exception('This bootstrap grant is not valid for owner setup.');
      }
      if (grantEmail != normalizedEmail) {
        throw Exception(
          'This bootstrap grant is tied to a different email address.',
        );
      }
      if (expiresAt is Timestamp &&
          DateTime.now().isAfter(expiresAt.toDate())) {
        throw Exception(
          'This owner bootstrap grant has expired. Ask an existing owner/admin for a fresh grant.',
        );
      }

      final existingUserSnapshot = await transaction.get(userRef);
      if (existingUserSnapshot.exists) {
        final existingVenueId =
            existingUserSnapshot.data()?['venueId'] as String? ?? '';
        final existingRole =
            (existingUserSnapshot.data()?['role'] as String? ?? '').trim();
        if (existingRole == UserRole.owner.name && existingVenueId.isNotEmpty) {
          throw Exception(
            'This owner account is already linked. Sign in instead of starting setup again.',
          );
        }
        throw Exception(
          'This account is already linked to a venue. Sign in instead or ask an owner/admin for help.',
        );
      }

      createdAt = DateTime.now();
      transaction.set(venueRef, {
        'name': venueName,
        'ownerUid': userId,
        'createdAt': createdAt.toIso8601String(),
        'active': true,
      });
      transaction.set(userRef, {
        'displayName': displayName,
        'role': UserRole.owner.name,
        'venueId': venueRef.id,
        'createdAt': createdAt.toIso8601String(),
        'active': true,
        'email': normalizedEmail,
      });
      transaction.update(grantRef, {
        'disabled': true,
        'usedAt': Timestamp.fromDate(createdAt),
        'usedByUid': userId,
        'venueId': venueRef.id,
      });
    });
    return _BootstrapOwnerResult(venueId: venueRef.id, createdAt: createdAt);
  }

  Future<_InviteRedemptionData> _redeemInviteInFirestore({
    required FirebaseFirestore firestore,
    required String venueId,
    required String inviteId,
    required String userId,
    required String email,
    required String displayName,
  }) async {
    final inviteRef = firestore
        .collection(FirestorePaths.invites(venueId))
        .doc(inviteId);
    final userRef = firestore.collection(FirestorePaths.users()).doc(userId);
    final venueRef = firestore.collection('venues').doc(venueId);
    late VenueInvite redeemedInvite;
    late String venueName;
    await firestore.runTransaction((transaction) async {
      final inviteSnapshot = await transaction.get(inviteRef);
      if (!inviteSnapshot.exists) {
        _logInviteEvent(
          'Invite redemption rejected venue=$venueId invite=$inviteId reason=missing_invite',
          level: 900,
        );
        throw Exception('This invite could not be found.');
      }
      final invite = FirestoreSerializers.venueInviteFromMap(
        inviteId,
        inviteSnapshot.data()!,
      );
      if (invite.disabled) {
        _logInviteEvent(
          'Invite redemption rejected venue=$venueId invite=$inviteId reason=disabled',
          level: 900,
        );
        throw Exception(
          'This invite has been paused. Ask your venue manager for a fresh link.',
        );
      }
      if (DateTime.now().isAfter(invite.expiresAt)) {
        _logInviteEvent(
          'Invite redemption rejected venue=$venueId invite=$inviteId reason=expired',
          level: 900,
        );
        throw Exception(
          'This invite has expired. Ask your venue manager for a fresh link.',
        );
      }
      if (invite.currentUses >= invite.maxUses) {
        _logInviteEvent(
          'Invite redemption rejected venue=$venueId invite=$inviteId reason=overused',
          level: 900,
        );
        throw Exception(
          'This invite has already reached its usage limit. Ask your venue manager for a fresh link.',
        );
      }
      if (invite.role == UserRole.owner) {
        _logInviteEvent(
          'Invite redemption rejected venue=$venueId invite=$inviteId reason=owner_role',
          level: 1000,
        );
        throw Exception(
          'Owner/admin access is not available through the public join flow.',
        );
      }

      final venueSnapshot = await transaction.get(venueRef);
      if (!venueSnapshot.exists) {
        _logInviteEvent(
          'Invite redemption continuing venue=$venueId invite=$inviteId reason=missing_venue_doc_fallback',
          level: 900,
        );
      }
      final existingUserSnapshot = await transaction.get(userRef);
      if (existingUserSnapshot.exists) {
        final existingVenueId =
            existingUserSnapshot.data()?['venueId'] as String? ?? '';
        final existingRole =
            existingUserSnapshot.data()?['role'] as String? ?? '';
        if (existingVenueId == invite.venueId &&
            existingRole == invite.role.name) {
          _logInviteEvent(
            'Invite redemption resumed for existing user doc venue=$venueId invite=$inviteId uid=$userId',
            level: 900,
          );
        } else {
          _logInviteEvent(
            'Invite redemption rejected venue=$venueId invite=$inviteId reason=user_doc_conflict uid=$userId',
            level: 1000,
          );
          throw Exception(
            'This account is already linked to a different venue. Sign in instead, or ask your venue manager for help.',
          );
        }
      }

      venueName = venueSnapshot.data()?['name'] as String? ?? 'Venue';
      transaction.set(userRef, {
        'displayName': displayName,
        'role': invite.role.name,
        'venueId': invite.venueId,
        'createdAt': DateTime.now().toIso8601String(),
        'active': true,
        'email': email,
        'inviteId': invite.id,
      });
      transaction.update(inviteRef, {'currentUses': invite.currentUses + 1});
      redeemedInvite = invite.copyWith(currentUses: invite.currentUses + 1);
    });
    return _InviteRedemptionData(invite: redeemedInvite, venueName: venueName);
  }

  Future<_ExistingInviteAssignment?> _loadExistingInviteAssignment({
    required FirebaseFirestore firestore,
    required String userId,
  }) async {
    final snapshot = await firestore
        .collection(FirestorePaths.users())
        .doc(userId)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    final roleString = (data['role'] as String? ?? '').trim().toLowerCase();
    return _ExistingInviteAssignment(
      venueId: data['venueId'] as String? ?? '',
      inviteId: data['inviteId'] as String? ?? '',
      role: switch (roleString) {
        'owner' => UserRole.owner,
        'manager' => UserRole.manager,
        'bartender' => UserRole.bartender,
        _ => null,
      },
    );
  }

  Future<bool> _rollbackInviteUser({
    required firebase_auth.FirebaseAuth auth,
    required firebase_auth.User user,
    required String venueId,
    required String inviteId,
  }) async {
    try {
      await user.delete();
      _logInviteEvent(
        'Invite rollback deleted orphan auth account venue=$venueId invite=$inviteId uid=${user.uid}',
        level: 900,
      );
      return true;
    } catch (error, stackTrace) {
      _logInviteEvent(
        'Invite rollback failed venue=$venueId invite=$inviteId uid=${user.uid} error=$error',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await auth.signOut();
      } catch (_) {}
      return false;
    }
  }

  void _logInviteEvent(
    String message, {
    int level = 800,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'InviteAuth',
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _InviteRedemptionData {
  const _InviteRedemptionData({required this.invite, required this.venueName});

  final VenueInvite invite;
  final String venueName;
}

class _BootstrapOwnerResult {
  const _BootstrapOwnerResult({required this.venueId, required this.createdAt});

  final String venueId;
  final DateTime createdAt;
}

class _ExistingInviteAssignment {
  const _ExistingInviteAssignment({
    required this.venueId,
    required this.inviteId,
    required this.role,
  });

  final String venueId;
  final String inviteId;
  final UserRole? role;
}

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({required this.environment});

  final AppEnvironment environment;
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUser> createManagerAccount({
    required String email,
    required String password,
    required String displayName,
    required String venueName,
  }) async {
    throw Exception(
      'Manager account creation is available only in Firebase mode.',
    );
  }

  @override
  Future<AppUser> signInManager({
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() ==
            environment.demoManagerEmail.toLowerCase() &&
        password == environment.demoManagerPassword) {
      _currentUser = AppUser(
        id: 'demo-manager',
        email: environment.demoManagerEmail,
        displayName: 'Demo venue manager',
        role: UserRole.manager,
        venueId: environment.defaultVenueId,
        venueName: 'Demo venue',
        createdAt: DateTime.now(),
        active: true,
      );
      return _currentUser!;
    }
    throw Exception(
      'Use the demo manager credentials from the sign-in screen, or switch APP_MODE to firebase with live config.',
    );
  }

  @override
  Future<AppUser> createVenueManagerAccount({
    required String venueId,
    required String venueName,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw Exception(
      'Direct manager account creation has been replaced by invite-only join links.',
    );
  }

  @override
  Future<VenueInvite> createVenueInvite({
    required String venueId,
    required UserRole role,
    required String createdBy,
    required DateTime expiresAt,
    required int maxUses,
  }) async {
    throw Exception('Venue invites are available only in Firebase mode.');
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
  }) async {
    throw Exception(
      'Venue invite management is available only in Firebase mode.',
    );
  }

  @override
  Future<void> deleteVenueInvite({
    required String venueId,
    required String inviteId,
  }) async {
    throw Exception(
      'Venue invite management is available only in Firebase mode.',
    );
  }

  @override
  Future<AppUser> redeemVenueInvite({
    required String venueId,
    required String inviteId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw Exception('Invite redemption is available only in Firebase mode.');
  }

  @override
  Future<List<AppUser>> listVenueUsers({required String venueId}) async {
    return _currentUser == null ? const [] : [_currentUser!];
  }

  @override
  Future<void> setVenueUserActive({
    required String venueId,
    required String userId,
    required bool active,
  }) async {
    throw Exception(
      'Venue user management is available only in Firebase mode.',
    );
  }

  @override
  Future<void> deleteVenueUser({
    required String venueId,
    required String userId,
  }) async {
    throw Exception(
      'Venue user management is available only in Firebase mode.',
    );
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class FirestoreTrainingRepository implements TrainingRepository {
  FirestoreTrainingRepository({required String venueId})
    : _textParser = RecipeTextParser(),
      _pdfExtractor = PdfRecipeExtractor(RecipeTextParser()),
      _venueId = venueId;

  String _venueId;
  final RecipeTextParser _textParser;
  final PdfRecipeExtractor _pdfExtractor;
  final List<Ingredient> _ingredients = [];
  final List<CocktailRecipe> _recipes = [];
  final List<BatchRecipe> _batches = [];
  final List<CocktailRecipe> _verifiedRecipesOverride = [];
  final List<BatchRecipe> _verifiedBatchesOverride = [];
  final List<WeeklyConcernSession> _weeklySessions = [];
  final List<QuizSession> _quizSessions = [];
  final List<QuizAttempt> _quizAttempts = [];
  RecipeImportResult? _latestImportResult;
  int _idCounter = 0;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);

  @override
  List<CocktailRecipe> get recipes => List.unmodifiable(_visibleRecipes);

  @override
  List<BatchRecipe> get batches => List.unmodifiable(_visibleBatches);

  @override
  List<WeeklyConcernSession> get weeklySessions =>
      List.unmodifiable(_weeklySessions.reversed);

  @override
  List<QuizSession> get quizSessions =>
      List.unmodifiable(_quizSessions.reversed);

  @override
  List<QuizAttempt> get quizAttempts =>
      List.unmodifiable(_quizAttempts.reversed);

  @override
  RecipeImportResult? get latestImportResult => _latestImportResult;

  @override
  void configureVenue(String venueId) {
    _venueId = venueId;
    _verifiedRecipesOverride.clear();
    _verifiedBatchesOverride.clear();
  }

  @override
  Future<void> initialize() async {
    _weeklySessions.clear();
    _quizAttempts.clear();
    _latestImportResult = null;
    await _loadApprovedRecipesAndIngredients();
  }

  @override
  Future<void> loadManagerData() async {
    await Future.wait([
      _loadWeeklySessionsAndSales(),
      _loadQuizAttempts(),
      _loadAllQuizSessions(),
    ]);
  }

  @override
  Future<void> loadBartenderData({required String userId}) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.quizAttempts(_venueId))
        .where('userId', isEqualTo: userId)
        .get();
    _quizAttempts
      ..clear()
      ..addAll(
        snapshot.docs.map(
          (doc) => FirestoreSerializers.quizAttemptFromMap(doc.id, doc.data()),
        ),
      );
  }

  @override
  Future<void> loadAdminData() async {
    await _loadDrafts();
  }

  @override
  Future<bool> ensureBundledCatalogLoaded() async {
    if (_recipes.isNotEmpty) {
      return false;
    }
    final catalog = await _loadBundledCatalog();
    final linkedBatches = catalog.batches
        .map((batch) => _normalizeBatch(batch, batches: catalog.batches))
        .toList();
    final linkedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: catalog.recipes
          .map((recipe) => _normalizeRecipe(recipe, batches: linkedBatches))
          .toList(),
      batches: linkedBatches,
    );
    final mergedIngredients = _buildGlobalIngredientCatalog(
      recipes: linkedRecipes,
      batches: linkedBatches,
      storedIngredients: const [],
    );
    _ingredients
      ..clear()
      ..addAll(mergedIngredients);
    _recipes
      ..clear()
      ..addAll(linkedRecipes);
    _batches
      ..clear()
      ..addAll(linkedBatches);
    developer.log(
      'Bundled cocktail catalog loaded directly as startup safety fallback cocktails=${_recipes.length} batches=${_batches.length} ingredients=${_ingredients.length}',
      name: 'TrainingCatalog',
      level: 900,
    );
    return _recipes.isNotEmpty;
  }

  Future<void> _loadApprovedRecipesAndIngredients() async {
    final catalog = await _loadBundledCatalog();
    QuerySnapshot<Map<String, dynamic>>? venueIngredientSnapshot;
    QuerySnapshot<Map<String, dynamic>>? venueRecipeSnapshot;
    QuerySnapshot<Map<String, dynamic>>? venueBatchSnapshot;
    QuerySnapshot<Map<String, dynamic>>? legacyIngredientSnapshot;
    QuerySnapshot<Map<String, dynamic>>? legacyRecipeSnapshot;
    QuerySnapshot<Map<String, dynamic>>? legacyBatchSnapshot;
    Object? remoteLoadError;
    StackTrace? remoteLoadStackTrace;

    try {
      venueIngredientSnapshot = await _firestore
          .collection(FirestorePaths.ingredients(_venueId))
          .get();
      venueRecipeSnapshot = await _firestore
          .collection(FirestorePaths.recipes(_venueId))
          .get();
      venueBatchSnapshot = await _firestore
          .collection(FirestorePaths.batchRecipes(_venueId))
          .get();
      legacyIngredientSnapshot = await _firestore
          .collection(FirestorePaths.cocktailIngredients())
          .get();
      legacyRecipeSnapshot = await _firestore
          .collection(FirestorePaths.cocktails())
          .get();
      legacyBatchSnapshot = await _firestore
          .collection(FirestorePaths.batches())
          .get();
      developer.log(
        'Cocktail list load success venue=$_venueId venueCocktails=${venueRecipeSnapshot.docs.length} venueBatches=${venueBatchSnapshot.docs.length} venueIngredients=${venueIngredientSnapshot.docs.length} legacyCocktails=${legacyRecipeSnapshot.docs.length} legacyBatches=${legacyBatchSnapshot.docs.length} legacyIngredients=${legacyIngredientSnapshot.docs.length}',
        name: 'TrainingCatalog',
      );
    } catch (error, stackTrace) {
      remoteLoadError = error;
      remoteLoadStackTrace = stackTrace;
      developer.log(
        'Global cocktail list load failed. Falling back to bundled catalog.',
        name: 'TrainingCatalog',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final storedBatchDocs = {
      for (final doc
          in legacyBatchSnapshot?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        doc.id: FirestoreSerializers.batchRecipeFromMap(doc.id, doc.data()),
      for (final doc
          in venueBatchSnapshot?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        doc.id: FirestoreSerializers.batchRecipeFromMap(doc.id, doc.data()),
    };
    final mergedBatchInputs = catalog.batches
        .map((batch) => storedBatchDocs[batch.id] ?? batch)
        .where((batch) => batch.isApproved)
        .toList();
    final mergedBatches = mergedBatchInputs
        .map((batch) => _normalizeBatch(batch, batches: mergedBatchInputs))
        .toList();

    final storedRecipeDocs = {
      for (final doc
          in legacyRecipeSnapshot?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        doc.id: FirestoreSerializers.recipeFromMap(doc.id, doc.data()),
      for (final doc
          in venueRecipeSnapshot?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        doc.id: FirestoreSerializers.recipeFromMap(doc.id, doc.data()),
    };
    final mergedRecipeInputs = catalog.recipes
        .map((recipe) => storedRecipeDocs[recipe.id] ?? recipe)
        .where((recipe) => recipe.isApproved)
        .toList();
    final relinkedCocktails = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: mergedRecipeInputs
          .map((recipe) => _normalizeRecipe(recipe, batches: mergedBatches))
          .toList(),
      batches: mergedBatches,
    );
    final mergedIngredients = _buildGlobalIngredientCatalog(
      recipes: relinkedCocktails,
      batches: mergedBatches,
      storedIngredients: [
        ...(legacyIngredientSnapshot?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(
              (doc) =>
                  FirestoreSerializers.ingredientFromMap(doc.id, doc.data()),
            ),
        ...(venueIngredientSnapshot?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(
              (doc) =>
                  FirestoreSerializers.ingredientFromMap(doc.id, doc.data()),
            ),
      ],
    );

    _ingredients
      ..clear()
      ..addAll(mergedIngredients);
    _recipes
      ..clear()
      ..addAll(relinkedCocktails);
    _batches
      ..clear()
      ..addAll(mergedBatches);

    if (remoteLoadError != null) {
      developer.log(
        'Bundled cocktail catalog is active after Firestore fallback cocktails=${_recipes.length} batches=${_batches.length} ingredients=${_ingredients.length}',
        name: 'TrainingCatalog',
        level: 900,
        error: remoteLoadError,
        stackTrace: remoteLoadStackTrace,
      );
    } else if (storedRecipeDocs.isEmpty && storedBatchDocs.isEmpty) {
      developer.log(
        'Bundled cocktail catalog is active because shared Firestore overrides are empty cocktails=${_recipes.length} batches=${_batches.length}',
        name: 'TrainingCatalog',
      );
    } else {
      developer.log(
        'Shared cocktail catalog overlay active firestoreCocktails=${storedRecipeDocs.length} firestoreBatches=${storedBatchDocs.length} finalCocktails=${_recipes.length} finalBatches=${_batches.length}',
        name: 'TrainingCatalog',
      );
    }
  }

  List<CocktailRecipe> get _visibleRecipes {
    if (_verifiedRecipesOverride.isNotEmpty) {
      return List.unmodifiable(_verifiedRecipesOverride);
    }
    return List.unmodifiable(_recipes);
  }

  List<BatchRecipe> get _visibleBatches {
    if (_verifiedBatchesOverride.isNotEmpty) {
      return List.unmodifiable(_verifiedBatchesOverride);
    }
    return List.unmodifiable(_batches);
  }

  Future<void> _loadDrafts() async {
    final snapshot = await _firestore
        .collection(FirestorePaths.recipeDrafts(_venueId))
        .get();
    final drafts = snapshot.docs
        .map((doc) => FirestoreSerializers.draftFromMap(doc.id, doc.data()))
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .toList();
    _latestImportResult = drafts.isEmpty
        ? null
        : _normalizeImportResult(
            RecipeImportResult(
              sourceName: 'Firestore review drafts',
              drafts: drafts,
              warnings: const [],
              requiresOcr: false,
              rawText: '',
              pageCount: 0,
            ),
          );
  }

  Future<void> _loadWeeklySessionsAndSales() async {
    final sessionSnapshot = await _firestore
        .collection(FirestorePaths.stockConcernSessions(_venueId))
        .get();
    final salesSnapshot = await _firestore
        .collection(FirestorePaths.bartenderSales(_venueId))
        .get();
    final salesByWeek = <String, List<BartenderWeeklySales>>{};
    for (final doc in salesSnapshot.docs) {
      final data = doc.data();
      final weekId = data['weekId'] as String? ?? '';
      if (weekId.isEmpty) {
        continue;
      }
      salesByWeek
          .putIfAbsent(weekId, () => [])
          .add(FirestoreSerializers.bartenderSalesFromMap(data));
    }
    _weeklySessions
      ..clear()
      ..addAll(
        sessionSnapshot.docs.map(
          (doc) => FirestoreSerializers.weeklySessionFromMap(
            doc.id,
            doc.data(),
            bartenderSales: salesByWeek[doc.id] ?? const [],
          ),
        ),
      );
  }

  Future<void> _loadAllQuizSessions() async {
    final snapshot = await _firestore
        .collection(FirestorePaths.quizSessions(_venueId))
        .get();
    _quizSessions
      ..clear()
      ..addAll(
        snapshot.docs.map(
          (doc) => FirestoreSerializers.quizSessionFromMap(doc.id, doc.data()),
        ),
      );
  }

  Future<void> _loadQuizAttempts() async {
    final snapshot = await _firestore
        .collection(FirestorePaths.quizAttempts(_venueId))
        .get();
    _quizAttempts
      ..clear()
      ..addAll(
        snapshot.docs.map(
          (doc) => FirestoreSerializers.quizAttemptFromMap(doc.id, doc.data()),
        ),
      );
  }

  @override
  Future<RecipeImportResult> extractRecipesFromPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _latestImportResult = _normalizeImportResult(
      _pdfExtractor.extract(bytes: bytes, fileName: fileName),
    );
    return _latestImportResult!;
  }

  @override
  RecipeImportResult extractRecipesFromText({
    required String text,
    required String sourceName,
  }) {
    _latestImportResult = _normalizeImportResult(
      _textParser.parseImportText(source: text, sourceName: sourceName),
    );
    return _latestImportResult!;
  }

  @override
  void clearImportPreview() {
    _latestImportResult = null;
  }

  @override
  Future<void> saveImportedDrafts(List<RecipeImportDraft> drafts) async {
    final approvedDrafts = drafts
        .where((draft) => draft.status == RecipeDraftStatus.approved)
        .toList();
    final pendingDrafts = drafts
        .where((draft) => draft.status == RecipeDraftStatus.pending)
        .toList();
    debugPrint(
      '[RecipeImport] Saving drafts venue=$_venueId approved=${approvedDrafts.length} pending=${pendingDrafts.length} total=${drafts.length}',
    );

    final batch = _firestore.batch();
    final draftCollection = _firestore.collection(
      FirestorePaths.recipeDrafts(_venueId),
    );
    final recipeCollection = _firestore.collection(
      FirestorePaths.recipes(_venueId),
    );
    final batchRecipeCollection = _firestore.collection(
      FirestorePaths.batchRecipes(_venueId),
    );
    final ingredientCollection = _firestore.collection(
      FirestorePaths.ingredients(_venueId),
    );

    for (final draft in drafts) {
      final draftDoc = draftCollection.doc(draft.id);
      if (draft.status == RecipeDraftStatus.deleted ||
          draft.status == RecipeDraftStatus.approved) {
        batch.delete(draftDoc);
      } else {
        batch.set(draftDoc, FirestoreSerializers.draftToMap(draft));
      }
    }

    final approvedBatchRecipes = approvedDrafts
        .where((draft) => draft.isBatch)
        .map((draft) {
          final batchRecipe = draft.toBatchRecipe();
          return _normalizeBatch(
            batchRecipe.copyWith(
              id: _resolvedBatchId(batchRecipe),
              isApproved: true,
              wasManuallyReviewed: true,
            ),
          );
        })
        .toList();
    for (final batchRecipe in approvedBatchRecipes) {
      batch.set(
        batchRecipeCollection.doc(batchRecipe.id),
        FirestoreSerializers.batchRecipeToMap(batchRecipe),
      );
    }

    final batchesAfterSave = {
      for (final batchRecipe in _batches) batchRecipe.id: batchRecipe,
      for (final batchRecipe in approvedBatchRecipes)
        batchRecipe.id: batchRecipe,
    }.values.toList();
    final normalizedApprovedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: approvedDrafts.where((draft) => !draft.isBatch).map((draft) {
        final recipe = draft.toRecipe();
        final existing = _findExistingRecipe(recipe);
        if (existing != null) {
          return _normalizeRecipe(
            existing.copyWith(
              isApproved: true,
              wasManuallyReviewed: true,
              priceGbp:
                  draft.priceGbp ??
                  recipe.priceGbp ??
                  approvedCocktailPriceGbpForName(draft.name) ??
                  existing.priceGbp,
            ),
            batches: batchesAfterSave,
          );
        }
        return _normalizeRecipe(
          recipe.copyWith(
            id: _resolvedRecipeId(recipe),
            isApproved: true,
            wasManuallyReviewed: true,
          ),
          batches: batchesAfterSave,
        );
      }).toList(),
      batches: batchesAfterSave,
    );
    final seenIngredientNames = <String>{};
    void queueIngredient(String rawName) {
      final trimmedName = rawName.trim();
      if (trimmedName.isEmpty) {
        return;
      }
      final normalizedName = trimmedName.toLowerCase();
      final alreadyStored = _ingredients.any(
        (item) => item.name.toLowerCase() == normalizedName,
      );
      if (alreadyStored || !seenIngredientNames.add(normalizedName)) {
        return;
      }
      final pendingIngredient = Ingredient(
        id: _nextId('ingredient'),
        name: trimmedName,
        bottleSizeMl: 700,
        bottleCost: 0,
      );
      batch.set(
        ingredientCollection.doc(pendingIngredient.id),
        FirestoreSerializers.ingredientToMap(pendingIngredient),
      );
    }

    for (final batchRecipe in approvedBatchRecipes) {
      for (final ingredient in batchRecipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        queueIngredient(ingredient.ingredientName);
      }
    }
    for (final recipe in normalizedApprovedRecipes) {
      batch.set(
        recipeCollection.doc(recipe.id),
        FirestoreSerializers.recipeToMap(recipe),
      );
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        queueIngredient(ingredient.ingredientName);
      }
    }

    try {
      await batch.commit();
    } catch (error) {
      debugPrint('[RecipeImport] Firebase save failed: $error');
      rethrow;
    }

    await _loadApprovedRecipesAndIngredients();
    await _loadDrafts();
    debugPrint('[RecipeImport] Firebase save completed venue=$_venueId');
  }

  @override
  Future<VerifiedRecipeSyncResult> syncVerifiedRecipes({
    required List<CocktailRecipe> recipes,
    required List<BatchRecipe> batches,
    bool overwriteExisting = false,
  }) async {
    var cocktailsAdded = 0;
    var cocktailsUpdated = 0;
    var cocktailsSkipped = 0;
    var batchesAdded = 0;
    var batchesUpdated = 0;
    var batchesSkipped = 0;
    var ingredientsAdded = 0;

    final syncedBatches = <BatchRecipe>[];
    for (final batch in batches) {
      final existing = _findExistingBatch(batch);
      if (existing != null && !overwriteExisting) {
        batchesSkipped += 1;
        continue;
      }
      syncedBatches.add(
        batch.copyWith(
          id: existing?.id ?? batch.id,
          sourceLabel: CuratedRecipeImporter.sourceLabel,
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      );
      if (existing == null) {
        batchesAdded += 1;
      } else {
        batchesUpdated += 1;
      }
    }

    final batchState = {for (final item in _batches) item.id: item};
    for (final batch in syncedBatches) {
      batchState[batch.id] = batch;
    }
    final finalBatchList = batchState.values.toList();
    final normalizedBatches = syncedBatches
        .map((batch) => _normalizeBatch(batch, batches: finalBatchList))
        .toList();

    final syncedRecipes = <CocktailRecipe>[];
    for (final recipe in recipes) {
      final existing = _findExistingRecipe(recipe);
      if (existing != null && !overwriteExisting) {
        final backfilled = _backfillRecipePrice(
          existing: existing,
          incoming: recipe,
        );
        if (backfilled != null) {
          saveRecipe(backfilled);
          cocktailsUpdated += 1;
        } else {
          cocktailsSkipped += 1;
        }
        continue;
      }
      syncedRecipes.add(
        recipe.copyWith(
          id: existing?.id ?? recipe.id,
          sourceLabel: CuratedRecipeImporter.sourceLabel,
          isApproved: true,
          wasManuallyReviewed: true,
        ),
      );
      if (existing == null) {
        cocktailsAdded += 1;
      } else {
        cocktailsUpdated += 1;
      }
    }

    final batchesAfterSave = {
      for (final batchRecipe in _batches) batchRecipe.id: batchRecipe,
      for (final batchRecipe in normalizedBatches) batchRecipe.id: batchRecipe,
    }.values.toList();
    final normalizedRecipes = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: syncedRecipes
          .map((recipe) => _normalizeRecipe(recipe, batches: batchesAfterSave))
          .toList(),
      batches: batchesAfterSave,
    );

    final seenIngredientNames = <String>{};
    void queueIngredient(String rawName) {
      final trimmedName = rawName.trim();
      if (trimmedName.isEmpty) {
        return;
      }
      final normalizedName = trimmedName.toLowerCase();
      final alreadyStored = _ingredients.any(
        (item) => item.name.toLowerCase() == normalizedName,
      );
      if (alreadyStored || !seenIngredientNames.add(normalizedName)) {
        return;
      }
      ingredientsAdded += 1;
      _storeIngredientLocally(_placeholderIngredient(trimmedName));
    }

    for (final batch in normalizedBatches) {
      for (final ingredient in batch.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        queueIngredient(ingredient.ingredientName);
      }
    }

    for (final recipe in normalizedRecipes) {
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        queueIngredient(ingredient.ingredientName);
      }
    }

    for (final batch in normalizedBatches) {
      saveBatch(batch);
    }
    for (final recipe in normalizedRecipes) {
      saveRecipe(recipe);
    }

    await _loadApprovedRecipesAndIngredients();

    return VerifiedRecipeSyncResult(
      cocktailsAdded: cocktailsAdded,
      cocktailsUpdated: cocktailsUpdated,
      cocktailsSkipped: cocktailsSkipped,
      batchesAdded: batchesAdded,
      batchesUpdated: batchesUpdated,
      batchesSkipped: batchesSkipped,
      ingredientsAdded: ingredientsAdded,
      flaggedCocktails: recipes.where((recipe) => recipe.needsReview).length,
      flaggedBatches: batches.where((batch) => batch.needsReview).length,
      missingImages: recipes.where((recipe) => recipe.missingImage).length,
    );
  }

  @override
  void saveIngredient(Ingredient ingredient) {
    _storeIngredientLocally(ingredient);
    unawaited(
      _firestore
          .collection(FirestorePaths.ingredients(_venueId))
          .doc(ingredient.id)
          .set(FirestoreSerializers.ingredientToMap(ingredient)),
    );
  }

  @override
  void saveRecipe(CocktailRecipe recipe) {
    final normalized = _normalizeRecipe(recipe);
    _storeRecipeLocally(normalized);
    unawaited(
      _firestore
          .collection(FirestorePaths.recipes(_venueId))
          .doc(normalized.id)
          .set(FirestoreSerializers.recipeToMap(normalized)),
    );
  }

  @override
  void saveBatch(BatchRecipe batch) {
    final normalized = _normalizeBatch(batch);
    _storeBatchLocally(normalized);
    unawaited(
      _firestore
          .collection(FirestorePaths.batchRecipes(_venueId))
          .doc(normalized.id)
          .set(FirestoreSerializers.batchRecipeToMap(normalized)),
    );
  }

  Future<VerifiedRecipeCatalog> _loadBundledCatalog() async {
    try {
      final cocktailJsonText = await _loadAssetText(
        CuratedRecipeImporter.cocktailAssetPath,
      );
      final batchJsonText = await _loadAssetText(
        CuratedRecipeImporter.batchAssetPath,
      );
      final catalog = const CuratedRecipeImporter().buildVerifiedCatalog(
        cocktailJsonText: cocktailJsonText,
        batchJsonText: batchJsonText,
      );
      developer.log(
        'Bundled catalog parsed cocktails=${catalog.recipes.length} batches=${catalog.batches.length} first=${catalog.recipes.isEmpty ? '<none>' : '${catalog.recipes.first.id}/${catalog.recipes.first.name}'}',
        name: 'TrainingCatalog',
      );
      return catalog;
    } catch (error, stackTrace) {
      developer.log(
        'Bundled catalog parse failed',
        name: 'TrainingCatalog',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Cocktail list could not be loaded. Please refresh or contact admin.',
      );
    }
  }

  Future<String> _loadAssetText(String assetKey) async {
    developer.log('Asset load start asset=$assetKey', name: 'TrainingCatalog');
    try {
      final text = await rootBundle.loadString(assetKey);
      developer.log(
        'Asset load success asset=$assetKey source=rootBundle chars=${text.length}',
        name: 'TrainingCatalog',
      );
      return text;
    } catch (error, stackTrace) {
      developer.log(
        'Asset load via rootBundle failed asset=$assetKey',
        name: 'TrainingCatalog',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      if (!kIsWeb) {
        rethrow;
      }
    }

    final webPath = '/assets/$assetKey';
    try {
      developer.log(
        'Asset web fallback start asset=$assetKey url=$webPath',
        name: 'TrainingCatalog',
      );
      final text = await NetworkAssetBundle(Uri.base).loadString(webPath);
      developer.log(
        'Asset web fallback success asset=$assetKey source=$webPath chars=${text.length}',
        name: 'TrainingCatalog',
      );
      return text;
    } catch (error, stackTrace) {
      developer.log(
        'Asset web fallback failed asset=$assetKey url=$webPath',
        name: 'TrainingCatalog',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  List<Ingredient> _buildGlobalIngredientCatalog({
    required List<CocktailRecipe> recipes,
    required List<BatchRecipe> batches,
    required List<Ingredient> storedIngredients,
  }) {
    final byKey = <String, Ingredient>{};
    void addPlaceholder(String rawName) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final key = trimmed.toLowerCase();
      byKey.putIfAbsent(key, () => _placeholderIngredient(trimmed));
    }

    for (final batch in batches) {
      for (final ingredient in batch.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        addPlaceholder(ingredient.ingredientName);
      }
    }
    for (final recipe in recipes) {
      for (final ingredient in recipe.ingredients.where(
        (item) => !item.isBatchReference,
      )) {
        addPlaceholder(ingredient.ingredientName);
      }
    }
    for (final ingredient in storedIngredients) {
      byKey[ingredient.name.trim().toLowerCase()] = ingredient;
    }
    return byKey.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Ingredient _placeholderIngredient(String name) {
    final normalizedId = BatchGraphResolver.normalizeKey(name);
    return Ingredient(
      id: normalizedId.isEmpty ? _nextId('ingredient') : normalizedId,
      name: name.trim(),
      bottleSizeMl: 700,
      bottleCost: 0,
    );
  }

  CocktailRecipe _normalizeRecipe(
    CocktailRecipe recipe, {
    List<BatchRecipe>? batches,
  }) {
    return BatchGraphResolver.linkCocktailsToBatches(
      cocktails: [
        recipe.copyWith(
          name: recipe.name.trim(),
          category: recipe.category.trim(),
          glassware: recipe.glassware.trim(),
          garnish: recipe.garnish.trim(),
          method: recipe.method.trim(),
          notes: recipe.notes.trim(),
          priceGbp:
              recipe.priceGbp ?? approvedCocktailPriceGbpForName(recipe.name),
          isApproved: true,
          ingredients: recipe.ingredients
              .where((item) => item.ingredientName.trim().isNotEmpty)
              .map(
                (item) =>
                    item.copyWith(ingredientName: item.ingredientName.trim()),
              )
              .toList(),
        ),
      ],
      batches: batches ?? _batches,
    ).single;
  }

  BatchRecipe _normalizeBatch(BatchRecipe batch, {List<BatchRecipe>? batches}) {
    final linkedIngredients = batch.ingredients
        .where((item) => item.ingredientName.trim().isNotEmpty)
        .map(
          (item) => item.copyWith(ingredientName: item.ingredientName.trim()),
        )
        .map(
          (item) => BatchGraphResolver.linkIngredientToBatch(
            ingredient: item,
            batchIndex: BatchGraphResolver.buildBatchIndex(
              (batches ?? _batches).where(
                (existing) => existing.id != batch.id,
              ),
            ),
          ),
        )
        .toList();
    return batch.copyWith(
      name: batch.name.trim(),
      category: batch.category.trim(),
      notes: batch.notes.trim(),
      isApproved: true,
      ingredients: linkedIngredients,
    );
  }

  void _storeRecipeLocally(CocktailRecipe recipe) {
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index == -1) {
      _recipes.add(recipe);
    } else {
      _recipes[index] = recipe;
    }
  }

  void _storeBatchLocally(BatchRecipe batch) {
    final index = _batches.indexWhere((item) => item.id == batch.id);
    if (index == -1) {
      _batches.add(batch);
    } else {
      _batches[index] = batch;
    }
    final relinked = BatchGraphResolver.linkCocktailsToBatches(
      cocktails: _recipes,
      batches: _batches,
    );
    _recipes
      ..clear()
      ..addAll(relinked);
  }

  void _storeIngredientLocally(Ingredient ingredient) {
    final index = _ingredients.indexWhere(
      (item) =>
          item.id == ingredient.id ||
          item.name.toLowerCase() == ingredient.name.toLowerCase(),
    );
    if (index == -1) {
      _ingredients.add(ingredient);
    } else {
      _ingredients[index] = ingredient;
    }
  }

  CocktailRecipe? _backfillRecipePrice({
    required CocktailRecipe existing,
    required CocktailRecipe incoming,
  }) {
    final incomingPrice =
        incoming.priceGbp ??
        approvedCocktailPriceGbpForName(incoming.name) ??
        approvedCocktailPriceGbpForName(existing.name);
    if (incomingPrice == null || existing.priceGbp == incomingPrice) {
      return null;
    }
    return existing.copyWith(priceGbp: incomingPrice);
  }

  CocktailRecipe? _findExistingRecipe(CocktailRecipe recipe) {
    final normalizedName = BatchGraphResolver.normalizeKey(recipe.name);
    final normalizedId = normalizeCocktailId(recipe.id);
    final approvedNameKey = approvedCocktailNameMatchKey(recipe.name);
    return _recipes.cast<CocktailRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (normalizeCocktailId(item.id) == normalizedId ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName ||
              approvedCocktailNamesMatch(item.name, recipe.name) ||
              approvedCocktailNameMatchKey(item.name) == approvedNameKey),
      orElse: () => null,
    );
  }

  BatchRecipe? _findExistingBatch(BatchRecipe batch) {
    final normalizedName = BatchGraphResolver.normalizeKey(batch.name);
    return _batches.cast<BatchRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (item.id == batch.id ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName),
      orElse: () => null,
    );
  }

  String _resolvedRecipeId(CocktailRecipe recipe) {
    final normalizedName = BatchGraphResolver.normalizeKey(recipe.name);
    final normalizedId = normalizeCocktailId(recipe.id);
    final approvedNameKey = approvedCocktailNameMatchKey(recipe.name);
    final existing = _recipes.cast<CocktailRecipe?>().firstWhere(
      (item) =>
          item != null &&
          (normalizeCocktailId(item.id) == normalizedId ||
              BatchGraphResolver.normalizeKey(item.name) == normalizedName ||
              approvedCocktailNamesMatch(item.name, recipe.name) ||
              approvedCocktailNameMatchKey(item.name) == approvedNameKey),
      orElse: () => null,
    );
    return normalizeCocktailId(existing?.id ?? recipe.id);
  }

  String _resolvedBatchId(BatchRecipe batch) {
    final normalizedName = BatchGraphResolver.normalizeKey(batch.name);
    final existing = _batches.cast<BatchRecipe?>().firstWhere(
      (item) =>
          item != null &&
          BatchGraphResolver.normalizeKey(item.name) == normalizedName,
      orElse: () => null,
    );
    return existing?.id ?? batch.id;
  }

  @override
  WeeklyConcernSession createWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final existing = _findMatchingWeeklySession(
      label: label,
      weekStart: weekStart,
      concerns: concerns,
    );
    if (existing != null) {
      return existing;
    }
    final concernNames = concerns
        .map((item) => BatchGraphResolver.normalizeKey(item.ingredientName))
        .toSet();
    final targetIds = _visibleRecipes
        .where(
          (recipe) => BatchGraphResolver.cocktailUsesConcernIngredient(
            cocktail: recipe,
            concernNames: concernNames,
            batches: _visibleBatches,
            ingredientsByName: _ingredientsByName,
          ),
        )
        .map((recipe) => recipe.id)
        .toList();

    final session = WeeklyConcernSession(
      id: _nextId('week'),
      label: label,
      weekStart: weekStart,
      concerns: concerns,
      targetCocktailIds: targetIds,
      bartenderSales: const [],
      quizSessionIds: const [],
    );
    _weeklySessions.add(session);
    unawaited(
      _firestore
          .collection(FirestorePaths.stockConcernSessions(_venueId))
          .doc(session.id)
          .set(FirestoreSerializers.weeklySessionToMap(session)),
    );
    return session;
  }

  @override
  void saveBartenderSales({
    required String weekId,
    required String bartenderName,
    required List<BartenderSalesEntry> entries,
  }) {
    final index = _weeklySessions.indexWhere((session) => session.id == weekId);
    if (index == -1) {
      return;
    }
    final current = _weeklySessions[index];
    final sales = [...current.bartenderSales];
    final salesIndex = sales.indexWhere(
      (record) =>
          record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
    );
    final updated = BartenderWeeklySales(
      bartenderName: bartenderName,
      entries: entries.where((entry) => entry.quantitySold > 0).toList(),
    );
    if (salesIndex == -1) {
      sales.add(updated);
    } else {
      sales[salesIndex] = updated;
    }
    _weeklySessions[index] = current.copyWith(bartenderSales: sales);
    final salesDocId =
        '$weekId-${bartenderName.toLowerCase().replaceAll(' ', '-')}';
    unawaited(
      _firestore
          .collection(FirestorePaths.bartenderSales(_venueId))
          .doc(salesDocId)
          .set(FirestoreSerializers.bartenderSalesToMap(weekId, updated)),
    );
  }

  @override
  QuizSession generateStockQuizSession({
    required String weekId,
    required String bartenderName,
  }) {
    final existing = _quizSessions.cast<QuizSession?>().firstWhere(
      (session) =>
          session != null &&
          session.weekId == weekId &&
          session.bartenderName.toLowerCase() == bartenderName.toLowerCase() &&
          session.isActive,
      orElse: () => null,
    );
    if (existing != null) {
      return existing;
    }
    final generated = _generateStockQuizLocally(
      weekId: weekId,
      bartenderName: bartenderName,
    );
    final quiz = generated.copyWith(weekId: weekId);
    _quizSessions.add(quiz);
    final weeklyIndex = _weeklySessions.indexWhere(
      (session) => session.id == weekId,
    );
    if (weeklyIndex != -1) {
      final weeklySession = _weeklySessions[weeklyIndex];
      _weeklySessions[weeklyIndex] = weeklySession.copyWith(
        quizSessionIds: [...weeklySession.quizSessionIds, quiz.id],
      );
      unawaited(
        _firestore
            .collection(FirestorePaths.stockConcernSessions(_venueId))
            .doc(weekId)
            .set(
              FirestoreSerializers.weeklySessionToMap(
                _weeklySessions[weeklyIndex],
              ),
            ),
      );
    }
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(quiz.id)
          .set(FirestoreSerializers.quizSessionToMap(quiz)),
    );
    return quiz;
  }

  QuizSession _generateStockQuizLocally({
    required String weekId,
    required String bartenderName,
  }) {
    final adapter = LocalTrainingRepository();
    for (final ingredient in _ingredients) {
      adapter.saveIngredient(ingredient);
    }
    for (final batch in _visibleBatches) {
      adapter.saveBatch(batch);
    }
    for (final recipe in _visibleRecipes) {
      adapter.saveRecipe(recipe);
    }
    for (final session in _weeklySessions) {
      final cloned = adapter.createWeeklySession(
        label: session.label,
        weekStart: session.weekStart,
        concerns: session.concerns,
      );
      for (final sales in session.bartenderSales) {
        adapter.saveBartenderSales(
          weekId: cloned.id,
          bartenderName: sales.bartenderName,
          entries: sales.entries,
        );
      }
      if (session.id == weekId) {
        return adapter.generateStockQuizSession(
          weekId: cloned.id,
          bartenderName: bartenderName,
        );
      }
    }
    throw StateError('Weekly session not found for quiz generation.');
  }

  @override
  QuizSession generatePracticeQuizSession({
    required String bartenderName,
    List<String>? focusRecipeIds,
  }) {
    final adapter = LocalTrainingRepository();
    for (final ingredient in _ingredients) {
      adapter.saveIngredient(ingredient);
    }
    for (final batch in _visibleBatches) {
      adapter.saveBatch(batch);
    }
    for (final recipe in _visibleRecipes) {
      adapter.saveRecipe(recipe);
    }
    final quiz = adapter.generatePracticeQuizSession(
      bartenderName: bartenderName,
      focusRecipeIds: focusRecipeIds,
    );
    _quizSessions.add(quiz);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(quiz.id)
          .set(FirestoreSerializers.quizSessionToMap(quiz)),
    );
    return quiz;
  }

  @override
  QuizAttempt submitQuizAttempt({
    required String sessionId,
    String? userId,
    required String bartenderName,
    required Map<String, String> answers,
  }) {
    final existingAttempt = _quizAttempts.cast<QuizAttempt?>().firstWhere(
      (attempt) =>
          attempt != null &&
          attempt.sessionId == sessionId &&
          attempt.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
      orElse: () => null,
    );
    if (existingAttempt != null) {
      return existingAttempt;
    }
    final sessionIndex = _quizSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    final session = _quizSessions[sessionIndex];
    if (!session.isActive) {
      throw Exception(
        'This quiz session is no longer active. Ask your manager for a fresh link.',
      );
    }
    final weeklySession = session.weekId == null
        ? null
        : _weeklySessions.firstWhere((item) => item.id == session.weekId);
    final sales =
        weeklySession?.bartenderSales.firstWhere(
          (record) =>
              record.bartenderName.toLowerCase() == bartenderName.toLowerCase(),
          orElse: () => BartenderWeeklySales(
            bartenderName: bartenderName,
            entries: const [],
          ),
        ) ??
        BartenderWeeklySales(bartenderName: bartenderName, entries: const []);
    final quantityByCocktail = {
      for (final entry in sales.entries) entry.cocktailId: entry.quantitySold,
    };
    final ingredientsByName = {
      for (final ingredient in _ingredients)
        BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
    };

    final responses = session.questions.map((question) {
      final selectedAnswer = answers[question.id] ?? '';
      final isCorrect = selectedAnswer == question.correctAnswer;
      final quantitySold = quantityByCocktail[question.cocktailId] ?? 0;
      double? deltaMl;
      if ((question.kind == QuestionKind.ingredientMeasure ||
              question.kind == QuestionKind.batchAmount) &&
          question.correctMeasureMl != null) {
        final selectedMl = _parseMeasure(selectedAnswer);
        if (selectedMl != null) {
          deltaMl = selectedMl - question.correctMeasureMl!;
        }
      }
      return QuestionResponse(
        question: question,
        selectedAnswer: selectedAnswer,
        isCorrect: isCorrect,
        quantitySold: quantitySold,
        deltaMl: deltaMl,
      );
    }).toList();

    final attempt = VarianceMath.buildAttempt(
      attemptId: _nextId('attempt'),
      sessionId: session.id,
      weekId: session.weekId,
      userId: userId,
      bartenderName: bartenderName,
      responses: responses,
      ingredientsByName: ingredientsByName,
      batches: _visibleBatches,
    );

    _quizAttempts.add(attempt);
    _quizSessions[sessionIndex] = session.copyWith(isActive: false);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizAttempts(_venueId))
          .doc(attempt.id)
          .set(FirestoreSerializers.quizAttemptToMap(attempt))
          .catchError(
            (error, stackTrace) => developer.log(
              'Quiz attempt save failed venue=$_venueId attempt=${attempt.id}',
              name: 'TrainingCatalog',
              level: 1000,
              error: error,
              stackTrace: stackTrace is StackTrace ? stackTrace : null,
            ),
          ),
    );
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(session.id)
          .set(
            FirestoreSerializers.quizSessionToMap(_quizSessions[sessionIndex]),
          )
          .catchError(
            (error, stackTrace) => developer.log(
              'Quiz session close save failed venue=$_venueId session=${session.id}',
              name: 'TrainingCatalog',
              level: 1000,
              error: error,
              stackTrace: stackTrace is StackTrace ? stackTrace : null,
            ),
          ),
    );
    final totalVarianceValue =
        attempt.overpourLines.fold<double>(
          0,
          (total, line) => total + line.approximateValue,
        ) +
        attempt.batchOverpourLines.fold<double>(
          0,
          (total, line) => total + line.approximateValue,
        );
    unawaited(
      _firestore
          .collection(FirestorePaths.trendSummaries(_venueId))
          .doc(bartenderName.toLowerCase().replaceAll(' ', '-'))
          .set(
            FirestoreSerializers.trendSummaryToMap(
              bartenderName: bartenderName,
              latestScorePercent: attempt.scorePercent,
              potentialVarianceValue: totalVarianceValue,
            ),
          )
          .catchError(
            (error, stackTrace) => developer.log(
              'Trend summary save failed venue=$_venueId bartender=$bartenderName',
              name: 'TrainingCatalog',
              level: 1000,
              error: error,
              stackTrace: stackTrace is StackTrace ? stackTrace : null,
            ),
          ),
    );
    return attempt;
  }

  @override
  Future<QuizSession?> fetchQuizSession(String sessionId) async {
    final cached = findQuizSession(sessionId);
    if (cached != null) {
      return cached;
    }
    try {
      final snapshot = await _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(sessionId)
          .get();
      if (!snapshot.exists) {
        return null;
      }
      final session = FirestoreSerializers.quizSessionFromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (!session.isActive) {
        return null;
      }
      final existingIndex = _quizSessions.indexWhere(
        (item) => item.id == session.id,
      );
      if (existingIndex == -1) {
        _quizSessions.add(session);
      } else {
        _quizSessions[existingIndex] = session;
      }
      return session;
    } on FirebaseException catch (error, stackTrace) {
      developer.log(
        'Quiz session fetch failed session=$sessionId venue=$_venueId',
        name: 'TrainingCatalog',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  QuizSession? findQuizSession(String sessionId) {
    for (final session in _quizSessions) {
      if (session.id == sessionId && session.isActive) {
        return session;
      }
    }
    return null;
  }

  @override
  void deactivateQuizSession(String sessionId) {
    final index = _quizSessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (index == -1) {
      return;
    }
    _quizSessions[index] = _quizSessions[index].copyWith(isActive: false);
    unawaited(
      _firestore
          .collection(FirestorePaths.quizSessions(_venueId))
          .doc(sessionId)
          .set(FirestoreSerializers.quizSessionToMap(_quizSessions[index])),
    );
  }

  double? _parseMeasure(String answer) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(answer);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    return '$prefix-$_idCounter';
  }

  WeeklyConcernSession? _findMatchingWeeklySession({
    required String label,
    required DateTime weekStart,
    required List<StockConcernItem> concerns,
  }) {
    final concernKey =
        concerns.map((item) => item.ingredientName.toLowerCase()).toList()
          ..sort();
    for (final session in _weeklySessions) {
      final sessionKey =
          session.concerns
              .map((item) => item.ingredientName.toLowerCase())
              .toList()
            ..sort();
      if (_sameDay(session.weekStart, weekStart) &&
          session.label.trim().toLowerCase() == label.trim().toLowerCase() &&
          '$sessionKey' == '$concernKey') {
        return session;
      }
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Map<String, Ingredient> get _ingredientsByName => {
    for (final ingredient in _ingredients)
      BatchGraphResolver.normalizeKey(ingredient.name): ingredient,
  };

  RecipeImportResult _normalizeImportResult(RecipeImportResult result) {
    final linkedDrafts = BatchGraphResolver.linkDrafts(result.drafts);
    return RecipeImportResult(
      sourceName: result.sourceName,
      drafts: linkedDrafts,
      warnings: result.warnings,
      requiresOcr: result.requiresOcr,
      rawText: result.rawText,
      pageCount: result.pageCount,
    );
  }
}
