import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/user_profile.dart';
import 'package:cocktail_training/services/session_service.dart';

class ProgressService {
  ProgressService._();

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final user = await SessionService.instance.getCurrentUser();
    if (user == null) {
      return null;
    }
    return UserProfile.fromUser(user).toMap();
  }

  static Future<AppUser?> getCurrentUser() {
    return SessionService.instance.getCurrentUser();
  }
}
