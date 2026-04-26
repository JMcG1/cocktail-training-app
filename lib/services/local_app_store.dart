import 'dart:convert';

import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/team.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAppStore {
  LocalAppStore._();

  static final LocalAppStore instance = LocalAppStore._();

  static const _usersKey = 'app_users_v1';
  static const _venuesKey = 'app_venues_v1';
  static const _invitesKey = 'app_invites_v1';
  static const _sessionUserIdKey = 'app_session_user_id_v1';
  static const _seededKey = 'app_seeded_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> initialize() async {
    final prefs = await _getPrefs();
    final seeded = prefs.getBool(_seededKey) ?? false;
    if (seeded) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    const venueId = 'venue-demo-lab';
    const managerId = 'manager-demo';

    final venue = Team(
      id: venueId,
      name: 'Cocktail Training Lab',
      createdBy: managerId,
      createdAtMillis: now,
    );

    final manager = AppUser(
      id: managerId,
      name: 'Venue Manager',
      email: 'manager@cocktailtraining.app',
      password: 'training123',
      role: UserRole.manager,
      venueId: venueId,
      active: true,
      createdAtMillis: now,
      lastSignInAtMillis: now,
    );

    await _saveVenues([venue]);
    await _saveUsers([manager]);
    await _saveInvites(const []);
    await prefs.setBool(_seededKey, true);
  }

  Future<List<AppUser>> loadUsers() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> saveUsers(List<AppUser> users) => _saveUsers(users);

  Future<void> _saveUsers(List<AppUser> users) async {
    final prefs = await _getPrefs();
    await prefs.setString(
      _usersKey,
      jsonEncode(users.map((user) => user.toJson()).toList(growable: false)),
    );
  }

  Future<List<Team>> loadVenues() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_venuesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Team.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> _saveVenues(List<Team> venues) async {
    final prefs = await _getPrefs();
    await prefs.setString(
      _venuesKey,
      jsonEncode(venues.map((venue) => venue.toJson()).toList(growable: false)),
    );
  }

  Future<List<InviteToken>> loadInvites() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_invitesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => InviteToken.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> saveInvites(List<InviteToken> invites) => _saveInvites(invites);

  Future<void> _saveInvites(List<InviteToken> invites) async {
    final prefs = await _getPrefs();
    await prefs.setString(
      _invitesKey,
      jsonEncode(invites.map((invite) => invite.toJson()).toList(growable: false)),
    );
  }

  Future<String?> loadSessionUserId() async {
    final prefs = await _getPrefs();
    return prefs.getString(_sessionUserIdKey);
  }

  Future<void> saveSessionUserId(String? userId) async {
    final prefs = await _getPrefs();
    if (userId == null || userId.isEmpty) {
      await prefs.remove(_sessionUserIdKey);
      return;
    }
    await prefs.setString(_sessionUserIdKey, userId);
  }
}
