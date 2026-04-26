import 'dart:async';
import 'dart:math';

import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/services/local_app_store.dart';

class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  final LocalAppStore _store = LocalAppStore.instance;
  final StreamController<AppUser?> _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  Stream<AppUser?> get authStateChanges => _controller.stream;
  AppUser? get currentUser => _currentUser;

  Future<void> initialize() async {
    await _store.initialize();
    final sessionUserId = await _store.loadSessionUserId();
    if (sessionUserId == null) {
      _currentUser = null;
      _controller.add(_currentUser);
      return;
    }

    final users = await _store.loadUsers();
    _currentUser = users.where((user) => user.id == sessionUserId).firstOrNull;
    _controller.add(_currentUser);
  }

  Future<AppUser?> getCurrentUser() async {
    if (_currentUser != null) {
      return _currentUser;
    }

    await initialize();
    return _currentUser;
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final users = await _store.loadUsers();
    final normalizedEmail = email.trim().toLowerCase();
    final user = users.where((item) => item.email.trim().toLowerCase() == normalizedEmail).firstOrNull;

    if (user == null) {
      return 'No account found for this email.';
    }

    if (user.password != password) {
      return 'Incorrect email or password.';
    }

    final updatedUser = user.copyWith(
      lastSignInAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final updatedUsers = [
      for (final item in users) item.id == updatedUser.id ? updatedUser : item,
    ];
    await _store.saveUsers(updatedUsers);
    await _setCurrentUser(updatedUser);
    return null;
  }

  Future<void> signOut() async {
    _currentUser = null;
    await _store.saveSessionUserId(null);
    _controller.add(null);
  }

  Future<JoinWithInviteResult> joinWithInvite({
    required String name,
    required String email,
    required String password,
    required InviteToken invite,
  }) async {
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
      return const JoinWithInviteResult(error: 'Password must be at least 6 characters.');
    }

    final users = await _store.loadUsers();
    final existingUser = users.where((user) => user.email.trim().toLowerCase() == trimmedEmail).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;

    AppUser userToSignIn;
    if (existingUser != null) {
      if (existingUser.password != trimmedPassword) {
        return const JoinWithInviteResult(error: 'This email already exists with a different password.');
      }
      if (existingUser.role != invite.role || existingUser.venueId != invite.venueId) {
        return const JoinWithInviteResult(
          error: 'This account already belongs to a different role or venue.',
        );
      }

      userToSignIn = existingUser.copyWith(
        name: trimmedName,
        lastSignInAtMillis: now,
      );
      final updatedUsers = [
        for (final user in users) user.id == userToSignIn.id ? userToSignIn : user,
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

    await _setCurrentUser(userToSignIn);
    return JoinWithInviteResult(user: userToSignIn);
  }

  Future<List<AppUser>> loadUsersForVenue(String venueId) async {
    final users = await _store.loadUsers();
    return users.where((user) => user.venueId == venueId).toList(growable: false);
  }

  Future<String?> venueNameFor(String venueId) async {
    final venues = await _store.loadVenues();
    return venues.where((venue) => venue.id == venueId).firstOrNull?.name;
  }

  Future<void> _setCurrentUser(AppUser user) async {
    _currentUser = user;
    await _store.saveSessionUserId(user.id);
    _controller.add(user);
  }

  String _randomId() {
    const characters = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(16, (_) => characters[random.nextInt(characters.length)]).join();
  }
}

class JoinWithInviteResult {
  const JoinWithInviteResult({
    this.user,
    this.error,
  });

  final AppUser? user;
  final String? error;

  bool get isSuccess => user != null && error == null;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
