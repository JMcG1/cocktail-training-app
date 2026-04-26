import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/user_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.venueId,
    required this.active,
    required this.createdAtMillis,
    this.lastSignInAtMillis,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      id: (data['id'] as String?)?.trim() ?? '',
      name: (data['name'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      role: UserRoleX.fromKey(data['role'] as String?),
      venueId: (data['venueId'] as String?)?.trim() ?? '',
      active: data['active'] as bool? ?? false,
      createdAtMillis: data['createdAtMillis'] as int? ?? 0,
      lastSignInAtMillis: data['lastSignInAtMillis'] as int?,
    );
  }

  factory UserProfile.fromUser(AppUser user) {
    return UserProfile(
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      venueId: user.venueId,
      active: user.active,
      createdAtMillis: user.createdAtMillis,
      lastSignInAtMillis: user.lastSignInAtMillis,
    );
  }

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String venueId;
  final bool active;
  final int createdAtMillis;
  final int? lastSignInAtMillis;

  bool get isManager => role == UserRole.manager;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role.key,
      'venueId': venueId,
      'active': active,
      'createdAtMillis': createdAtMillis,
      'lastSignInAtMillis': lastSignInAtMillis,
    };
  }
}
