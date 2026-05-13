import '../../core/config/app_environment.dart';

class RepositoryModeResolver {
  const RepositoryModeResolver._();

  static bool shouldUseFirebase({
    required AppEnvironment environment,
    required bool firebaseAvailable,
  }) {
    switch (environment.appMode) {
      case AppMode.firebase:
        return firebaseAvailable;
      case AppMode.demo:
        return false;
      case AppMode.auto:
        return firebaseAvailable;
    }
  }
}
