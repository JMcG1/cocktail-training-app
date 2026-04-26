enum UserRole {
  manager,
  staff,
}

extension UserRoleX on UserRole {
  String get key => name;

  String get label {
    switch (this) {
      case UserRole.manager:
        return 'Manager';
      case UserRole.staff:
        return 'Staff';
    }
  }

  String get inviteLabel {
    switch (this) {
      case UserRole.manager:
        return 'Manager invite';
      case UserRole.staff:
        return 'Staff invite';
    }
  }

  static UserRole fromKey(String? value) {
    switch (value) {
      case 'manager':
        return UserRole.manager;
      case 'staff':
      default:
        return UserRole.staff;
    }
  }
}
