class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.role,
    required this.venueId,
    required this.active,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      name: (data['name'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      role: (data['role'] as String?)?.trim() ?? '',
      venueId: (data['venueId'] as String?)?.trim(),
      active: data['active'] as bool? ?? false,
    );
  }

  final String name;
  final String email;
  final String role;
  final String? venueId;
  final bool active;

  bool get isManager => role == 'manager';
}
