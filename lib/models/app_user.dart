import 'package:cocktail_training/models/user_role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.venueId,
    required this.active,
    required this.createdAtMillis,
    this.lastSignInAtMillis,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      password: json['password'] as String? ?? '',
      role: UserRoleX.fromKey(json['role'] as String?),
      venueId: json['venueId'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
      lastSignInAtMillis: json['lastSignInAtMillis'] as int?,
    );
  }

  final String id;
  final String name;
  final String email;
  final String password;
  final UserRole role;
  final String venueId;
  final bool active;
  final int createdAtMillis;
  final int? lastSignInAtMillis;

  bool get isManager => role == UserRole.manager;

  AppUser copyWith({
    String? name,
    String? email,
    String? password,
    UserRole? role,
    String? venueId,
    bool? active,
    int? createdAtMillis,
    int? lastSignInAtMillis,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      role: role ?? this.role,
      venueId: venueId ?? this.venueId,
      active: active ?? this.active,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      lastSignInAtMillis: lastSignInAtMillis ?? this.lastSignInAtMillis,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'password': password,
      'role': role.key,
      'venueId': venueId,
      'active': active,
      'createdAtMillis': createdAtMillis,
      'lastSignInAtMillis': lastSignInAtMillis,
    };
  }
}
