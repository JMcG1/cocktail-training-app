import 'package:firebase_core/firebase_core.dart';

import 'app_environment.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({required this.initialized, this.error});

  final bool initialized;
  final Object? error;

  String? get errorSummary => error?.toString();
}

class FirebaseBootstrap {
  static Future<FirebaseBootstrapResult> initializeIfPossible(
    AppEnvironment environment,
  ) async {
    if (!environment.hasRequiredFirebaseConfig) {
      return const FirebaseBootstrapResult(initialized: false);
    }

    if (Firebase.apps.isNotEmpty) {
      return const FirebaseBootstrapResult(initialized: true);
    }

    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: environment.firebaseApiKey,
          appId: environment.firebaseAppId,
          messagingSenderId: environment.firebaseMessagingSenderId,
          projectId: environment.firebaseProjectId,
          authDomain: environment.firebaseAuthDomain.isEmpty
              ? null
              : environment.firebaseAuthDomain,
          storageBucket: environment.firebaseStorageBucket.isEmpty
              ? null
              : environment.firebaseStorageBucket,
        ),
      );
      return const FirebaseBootstrapResult(initialized: true);
    } catch (error) {
      return FirebaseBootstrapResult(initialized: false, error: error);
    }
  }
}
