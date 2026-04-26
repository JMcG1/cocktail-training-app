import 'package:cocktail_training/models/app_user.dart';

class RoleGuard {
  const RoleGuard._();

  static bool canAccessManagerTools(AppUser? user) => user?.isManager ?? false;
}
