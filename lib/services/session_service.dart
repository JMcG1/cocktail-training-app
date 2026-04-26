import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/backend_runtime_service.dart';
import 'package:cocktail_training/services/local_app_store.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  static const _usersCollection = 'users';
  static const _invitesCollection = 'invites';
  static const _venuesCollection = 'venues';

  final LocalAppStore _store = LocalAppStore.instance;
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  StreamSubscription<User?>? _firebaseAuthSubscription;
  AppUser? _currentUser;
  bool _initialized = false;

  Stream<AppUser?> get authStateChanges => _controller.stream;
  AppUser? get currentUser => _currentUser;
  bool get _useFirebaseAuth => BackendRuntimeService.instance.useFirebaseAuth;
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> initialize() async {
    if (_initialized) {
      if (_useFirebaseAuth && _firebaseAuth.currentUser != null) {
        await _syncFirebaseUser(_firebaseAuth.currentUser);
      } else if (!_useFirebaseAuth) {
        await _loadLocalSession();
      }
      return;
    }

    if (_useFirebaseAuth) {
      debugPrint('[SessionService] Initializing Firebase-backed auth.');
      _firebaseAuthSubscription ??= _firebaseAuth.authStateChanges().listen((
        firebaseUser,
      ) async {
        await _syncFirebaseUser(firebaseUser);
      });
      await _syncFirebaseUser(_firebaseAuth.currentUser);
    } else {
      await _loadLocalSession();
    }

    _initialized = true;
  }

  Future<AppUser?> getCurrentUser() async {
    if (_currentUser != null) {
      return _currentUser;
    }

    await initialize();
    if (_useFirebaseAuth &&
        _currentUser == null &&
        _firebaseAuth.currentUser != null) {
      await _syncFirebaseUser(_firebaseAuth.currentUser);
    }
    return _currentUser;
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    return _useFirebaseAuth
        ? _signInWithFirebase(email: email, password: password)
        : _signInLocally(email: email, password: password);
  }

  Future<void> signOut() async {
    debugPrint(
      '[SessionService] Signing out ${_currentUser?.email ?? 'anonymous user'}.',
    );
    _currentUser = null;

    if (_useFirebaseAuth) {
      await _firebaseAuth.signOut();
    } else {
      await _store.saveSessionUserId(null);
      _controller.add(null);
    }
  }

  Future<JoinWithInviteResult> joinWithInvite({
    required String name,
    required String email,
    required String password,
    required InviteToken invite,
  }) async {
    return _useFirebaseAuth
        ? _joinWithFirebase(
            name: name,
            email: email,
            password: password,
            invite: invite,
          )
        : _joinLocally(
            name: name,
            email: email,
            password: password,
            invite: invite,
          );
  }

  Future<List<AppUser>> loadUsersForVenue(String venueId) async {
    if (_useFirebaseAuth) {
      final querySnapshot = await _firestore
          .collection(_usersCollection)
          .where('venueId', isEqualTo: venueId)
          .get();

      return querySnapshot.docs
          .map((doc) => AppUser.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
    }

    final users = await _store.loadUsers();
    return users
        .where((user) => user.venueId == venueId)
        .toList(growable: false);
  }

  Future<String?> venueNameFor(String venueId) async {
    if (_useFirebaseAuth) {
      final venueSnapshot = await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .get();
      if (!venueSnapshot.exists) {
        return null;
      }

      final data = venueSnapshot.data();
      return data?['name'] as String?;
    }

    final venues = await _store.loadVenues();
    return venues.where((venue) => venue.id == venueId).firstOrNull?.name;
  }

  Future<void> _syncFirebaseUser(User? firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null;
      debugPrint('[SessionService] Firebase auth state is signed out.');
      _controller.add(null);
      return;
    }

    final profile = await _loadFirestoreUser(firebaseUser.uid);
    if (profile == null) {
      debugPrint(
        '[SessionService] Firebase user ${firebaseUser.uid} has no Firestore profile yet.',
      );
      _currentUser = null;
      _controller.add(null);
      return;
    }

    _currentUser = profile;
    debugPrint(
      '[SessionService] Firebase session loaded for ${profile.email}.',
    );
    _controller.add(profile);
  }

  Future<void> _loadLocalSession() async {
    debugPrint('[SessionService] Initializing local session store.');
    await _store.initialize();
    final sessionUserId = await _store.loadSessionUserId();
    if (sessionUserId == null) {
      _currentUser = null;
      debugPrint('[SessionService] No persisted session found.');
      _controller.add(_currentUser);
      return;
    }

    final users = await _store.loadUsers();
    _currentUser = users.where((user) => user.id == sessionUserId).firstOrNull;
    debugPrint(
      '[SessionService] Restored session for '
      '${_currentUser?.email ?? 'unknown user id $sessionUserId'}.',
    );
    _controller.add(_currentUser);
  }

  Future<AppUser?> _loadFirestoreUser(String uid) async {
    final snapshot = await _firestore
        .collection(_usersCollection)
        .doc(uid)
        .get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return AppUser.fromFirestore(uid, data);
  }

  Future<String?> _signInWithFirebase({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    debugPrint(
      '[SessionService] Firebase sign-in attempt for $normalizedEmail.',
    );

    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return 'Login did not complete. Please try again.';
      }

      final profile = await _loadFirestoreUser(firebaseUser.uid);
      if (profile == null) {
        await _firebaseAuth.signOut();
        debugPrint(
          '[SessionService] Firebase sign-in failed: missing users/${firebaseUser.uid} document.',
        );
        return 'Your account signed in, but your training profile is missing. Ask a manager to re-send your invite.';
      }

      final updatedUser = profile.copyWith(
        lastSignInAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _firestore
          .collection(_usersCollection)
          .doc(firebaseUser.uid)
          .set(updatedUser.toFirestore(), SetOptions(merge: true));

      _currentUser = updatedUser;
      _controller.add(updatedUser);
      debugPrint(
        '[SessionService] Firebase sign-in succeeded for ${updatedUser.email}.',
      );
      return null;
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint('[SessionService] Firebase sign-in error: ${error.code}');
      debugPrint('$stackTrace');
      return _firebaseAuthMessage(error);
    } catch (error, stackTrace) {
      debugPrint('[SessionService] Unexpected Firebase sign-in error: $error');
      debugPrint('$stackTrace');
      return 'Login is unavailable right now. Please try again in a moment.';
    }
  }

  Future<JoinWithInviteResult> _joinWithFirebase({
    required String name,
    required String email,
    required String password,
    required InviteToken invite,
  }) async {
    debugPrint(
      '[SessionService] Firebase join attempt for ${email.trim().toLowerCase()} '
      'with role ${invite.role.key}.',
    );

    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPassword = password.trim();

    if (trimmedName.isEmpty) {
      return const JoinWithInviteResult(error: 'Enter your full name.');
    }
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return const JoinWithInviteResult(error: 'Enter a valid email address.');
    }
    if (trimmedPassword.length < 6) {
      return const JoinWithInviteResult(
        error: 'Password must be at least 6 characters.',
      );
    }

    UserCredential? credential;
    var createdAuthUser = false;

    try {
      try {
        credential = await _firebaseAuth.createUserWithEmailAndPassword(
          email: trimmedEmail,
          password: trimmedPassword,
        );
        createdAuthUser = true;
      } on FirebaseAuthException catch (error) {
        if (error.code != 'email-already-in-use') {
          return JoinWithInviteResult(error: _firebaseAuthMessage(error));
        }

        try {
          credential = await _firebaseAuth.signInWithEmailAndPassword(
            email: trimmedEmail,
            password: trimmedPassword,
          );
        } on FirebaseAuthException catch (_) {
          return const JoinWithInviteResult(
            error: 'This email already exists with a different password.',
          );
        }
      }

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return const JoinWithInviteResult(
          error: 'Account creation did not complete. Please try again.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final inviteRef = _firestore
          .collection(_invitesCollection)
          .doc(invite.token);
      final userRef = _firestore
          .collection(_usersCollection)
          .doc(firebaseUser.uid);

      await _firestore.runTransaction((transaction) async {
        final inviteSnapshot = await transaction.get(inviteRef);
        if (!inviteSnapshot.exists) {
          throw const _JoinFlowException('This invite link does not exist.');
        }

        final inviteData = inviteSnapshot.data();
        if (inviteData == null) {
          throw const _JoinFlowException('This invite could not be loaded.');
        }

        final currentInvite = InviteToken.fromFirestore(
          inviteSnapshot.id,
          inviteData,
        );
        if (!currentInvite.active) {
          throw const _JoinFlowException('This invite has been deactivated.');
        }
        if (currentInvite.isExpired) {
          throw const _JoinFlowException('This invite has expired.');
        }
        if (currentInvite.isUsedUp) {
          throw const _JoinFlowException(
            'This invite has already been fully used.',
          );
        }

        final existingUserSnapshot = await transaction.get(userRef);
        if (existingUserSnapshot.exists) {
          final existingData = existingUserSnapshot.data();
          if (existingData != null) {
            final existingUser = AppUser.fromFirestore(
              existingUserSnapshot.id,
              existingData,
            );
            if (existingUser.role != currentInvite.role ||
                existingUser.venueId != currentInvite.venueId) {
              throw const _JoinFlowException(
                'This account already belongs to a different role or venue.',
              );
            }
          }
        }

        final newUser = AppUser(
          id: firebaseUser.uid,
          name: trimmedName,
          email: trimmedEmail,
          role: currentInvite.role,
          venueId: currentInvite.venueId,
          active: true,
          createdAtMillis: existingUserSnapshot.exists
              ? AppUser.fromFirestore(
                  existingUserSnapshot.id,
                  existingUserSnapshot.data()!,
                ).createdAtMillis
              : now,
          lastSignInAtMillis: now,
        );

        transaction.set(
          userRef,
          newUser.toFirestore(),
          SetOptions(merge: true),
        );

        final newUsedCount = currentInvite.usedCount + 1;
        transaction.update(inviteRef, {
          'active': newUsedCount < currentInvite.maxUses
              ? currentInvite.active
              : false,
          'usedCount': newUsedCount,
        });
      });

      final profile = await _loadFirestoreUser(firebaseUser.uid);
      if (profile == null) {
        throw const _JoinFlowException(
          'Your account was created, but the training profile could not be loaded.',
        );
      }

      _currentUser = profile;
      _controller.add(profile);
      debugPrint(
        '[SessionService] Firebase join succeeded for ${profile.email}.',
      );
      return JoinWithInviteResult(user: profile);
    } on _JoinFlowException catch (error, stackTrace) {
      debugPrint(
        '[SessionService] Firebase join validation error: ${error.message}',
      );
      debugPrint('$stackTrace');
      if (createdAuthUser) {
        await credential?.user?.delete();
      }
      return JoinWithInviteResult(error: error.message);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[SessionService] Firebase join write error: ${error.code}');
      debugPrint('$stackTrace');
      if (createdAuthUser) {
        await credential?.user?.delete();
      }
      return const JoinWithInviteResult(
        error:
            'We couldn’t save your training profile right now. Please try again.',
      );
    } catch (error, stackTrace) {
      debugPrint('[SessionService] Unexpected Firebase join error: $error');
      debugPrint('$stackTrace');
      if (createdAuthUser) {
        await credential?.user?.delete();
      }
      return const JoinWithInviteResult(
        error: 'We couldn’t complete your join request right now.',
      );
    }
  }

  Future<String?> _signInLocally({
    required String email,
    required String password,
  }) async {
    debugPrint(
      '[SessionService] Local sign-in attempt for ${email.trim().toLowerCase()}.',
    );
    final users = await _store.loadUsers();
    final normalizedEmail = email.trim().toLowerCase();
    final user = users
        .where((item) => item.email.trim().toLowerCase() == normalizedEmail)
        .firstOrNull;

    if (user == null) {
      debugPrint('[SessionService] Local sign-in failed: user not found.');
      return 'We couldn’t find an account for that email yet. Check your invite or ask a manager to resend access.';
    }

    if (user.password != password) {
      debugPrint('[SessionService] Local sign-in failed: password mismatch.');
      return 'Incorrect email or password.';
    }

    final updatedUser = user.copyWith(
      lastSignInAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final updatedUsers = [
      for (final item in users) item.id == updatedUser.id ? updatedUser : item,
    ];
    await _store.saveUsers(updatedUsers);
    await _setLocalCurrentUser(updatedUser);
    debugPrint(
      '[SessionService] Local sign-in succeeded for ${updatedUser.email}.',
    );
    return null;
  }

  Future<JoinWithInviteResult> _joinLocally({
    required String name,
    required String email,
    required String password,
    required InviteToken invite,
  }) async {
    debugPrint(
      '[SessionService] Local join attempt for ${email.trim().toLowerCase()} '
      'with role ${invite.role.key}.',
    );
    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPassword = password.trim();

    if (trimmedName.isEmpty) {
      return const JoinWithInviteResult(error: 'Enter your full name.');
    }
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return const JoinWithInviteResult(error: 'Enter a valid email address.');
    }
    if (trimmedPassword.length < 6) {
      return const JoinWithInviteResult(
        error: 'Password must be at least 6 characters.',
      );
    }

    final users = await _store.loadUsers();
    final existingUser = users
        .where((user) => user.email.trim().toLowerCase() == trimmedEmail)
        .firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;

    AppUser userToSignIn;
    if (existingUser != null) {
      if (existingUser.password != trimmedPassword) {
        return const JoinWithInviteResult(
          error: 'This email already exists with a different password.',
        );
      }
      if (existingUser.role != invite.role ||
          existingUser.venueId != invite.venueId) {
        return const JoinWithInviteResult(
          error: 'This account already belongs to a different role or venue.',
        );
      }

      userToSignIn = existingUser.copyWith(
        name: trimmedName,
        lastSignInAtMillis: now,
      );
      final updatedUsers = [
        for (final user in users)
          user.id == userToSignIn.id ? userToSignIn : user,
      ];
      await _store.saveUsers(updatedUsers);
    } else {
      userToSignIn = AppUser(
        id: _randomId(),
        name: trimmedName,
        email: trimmedEmail,
        password: trimmedPassword,
        role: invite.role,
        venueId: invite.venueId,
        active: true,
        createdAtMillis: now,
        lastSignInAtMillis: now,
      );
      await _store.saveUsers([...users, userToSignIn]);
    }

    await _consumeLocalInvite(invite.token);
    await _setLocalCurrentUser(userToSignIn);
    debugPrint(
      '[SessionService] Local join succeeded for ${userToSignIn.email}.',
    );
    return JoinWithInviteResult(user: userToSignIn);
  }

  Future<void> _consumeLocalInvite(String token) async {
    final invites = await _store.loadInvites();
    final updated = [
      for (final invite in invites)
        if (invite.token == token)
          invite.copyWith(
            usedCount: invite.usedCount + 1,
            active: invite.usedCount + 1 < invite.maxUses
                ? invite.active
                : false,
          )
        else
          invite,
    ];
    await _store.saveInvites(updated);
  }

  Future<void> _setLocalCurrentUser(AppUser user) async {
    _currentUser = user;
    await _store.saveSessionUserId(user.id);
    debugPrint('[SessionService] Current user set to ${user.email}.');
    _controller.add(user);
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'invalid-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'email-already-in-use':
        return 'This email is already in use.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Auth yet.';
      case 'network-request-failed':
        return 'We couldn’t reach the login service. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts right now. Please wait a moment and try again.';
      default:
        return 'Login is unavailable right now. Please try again in a moment.';
    }
  }

  String _randomId() {
    const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      16,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }
}

class JoinWithInviteResult {
  const JoinWithInviteResult({this.user, this.error});

  final AppUser? user;
  final String? error;

  bool get isSuccess => user != null && error == null;
}

class _JoinFlowException implements Exception {
  const _JoinFlowException(this.message);

  final String message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
