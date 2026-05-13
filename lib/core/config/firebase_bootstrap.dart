import 'package:firebase_core/firebase_core.dart';

import 'app_environment.dart';

class FirebaseBootstrap {
  static Future<bool> initializeIfPossible(AppEnvironment environment) async {
    if (!environment.hasFirebaseConfig) {
      return false;
    }

    if (Firebase.apps.isNotEmpty) {
      return true;
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
      return true;
    } catch (_) {
      return false;
    }
  }
}
