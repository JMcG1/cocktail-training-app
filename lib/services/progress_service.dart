import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/session_service.dart';

class ProgressService {
  ProgressService._();

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final user = await SessionService.instance.getCurrentUser();
    if (user == null) {
      return null;
    }
    return _toProfileMap(user);
  }

  static Future<AppUser?> getCurrentUser() {
    return SessionService.instance.getCurrentUser();
  }

  static Map<String, dynamic> _toProfileMap(AppUser user) {
    return {
      'name': user.name,
      'email': user.email,
      'role': user.role.key,
      'venueId': user.venueId,
      'active': user.active,
    };
  }
}
