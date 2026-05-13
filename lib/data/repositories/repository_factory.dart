import '../../core/config/app_environment.dart';
import '../../core/config/firebase_bootstrap.dart';
import '../../domain/repositories/repositories.dart';
import 'demo_repositories.dart';
import 'firebase_repositories.dart';
import 'repository_mode_resolver.dart';

class RepositoryBundle {
  const RepositoryBundle({
    required this.authRepository,
    required this.trainingRepository,
    required this.usingFirebase,
  });

  final AuthRepository authRepository;
  final TrainingRepository trainingRepository;
  final bool usingFirebase;
}

class RepositoryFactory {
  const RepositoryFactory._();

  static Future<RepositoryBundle> create(AppEnvironment environment) async {
    final bootstrapResult = environment.appMode == AppMode.demo
        ? const FirebaseBootstrapResult(initialized: false)
        : await FirebaseBootstrap.initializeIfPossible(environment);
    final firebaseAvailable = bootstrapResult.initialized;

    if (environment.appMode == AppMode.firebase && !firebaseAvailable) {
      final errorSummary = bootstrapResult.errorSummary;
      throw Exception(
        errorSummary == null || errorSummary.isEmpty
            ? 'APP_MODE is set to firebase, but Firebase could not be initialized. Check the web config values first.'
            : 'APP_MODE is set to firebase, but Firebase could not be initialized. $errorSummary',
      );
    }

    if (RepositoryModeResolver.shouldUseFirebase(
      environment: environment,
      firebaseAvailable: firebaseAvailable,
    )) {
      return RepositoryBundle(
        authRepository: FirebaseManagerAuthRepository(environment: environment),
        trainingRepository: FirestoreTrainingRepository(
          venueId: environment.defaultVenueId,
        ),
        usingFirebase: true,
      );
    }

    return RepositoryBundle(
      authRepository: DemoAuthRepository(environment: environment),
      trainingRepository: LocalTrainingRepository(),
      usingFirebase: false,
    );
  }
}
