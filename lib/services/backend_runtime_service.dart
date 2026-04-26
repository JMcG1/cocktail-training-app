import 'package:cocktail_training/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum BackendAuthMode { localMock, firebaseAuthFirestore }

class BackendRuntimeSnapshot {
  const BackendRuntimeSnapshot({
    required this.authMode,
    required this.cloudflareHostingDetected,
    required this.firebaseConfiguredForWeb,
    required this.firebaseInitialized,
    this.firebaseMessage,
  });

  final BackendAuthMode authMode;
  final bool cloudflareHostingDetected;
  final bool firebaseConfiguredForWeb;
  final bool firebaseInitialized;
  final String? firebaseMessage;

  String get authModeLabel {
    switch (authMode) {
      case BackendAuthMode.localMock:
        return 'local_mock';
      case BackendAuthMode.firebaseAuthFirestore:
        return 'firebase_auth_firestore';
    }
  }
}

class BackendRuntimeService {
  BackendRuntimeService._();

  static final BackendRuntimeService instance = BackendRuntimeService._();

  BackendRuntimeSnapshot _snapshot = const BackendRuntimeSnapshot(
    authMode: BackendAuthMode.localMock,
    cloudflareHostingDetected: false,
    firebaseConfiguredForWeb: true,
    firebaseInitialized: false,
    firebaseMessage: 'Backend diagnostics have not run yet.',
  );

  BackendRuntimeSnapshot get snapshot => _snapshot;

  Future<void> initialize() async {
    final hostingOrigin = kIsWeb ? Uri.base.origin : '';

    final cloudflareHostingDetected =
        hostingOrigin.contains('pages.dev') ||
            hostingOrigin.contains('cloudflare');

    bool firebaseInitialized = false;
    String? firebaseMessage;

    final hasWebFirebaseConfig =
        DefaultFirebaseOptions.web.apiKey.isNotEmpty &&
        DefaultFirebaseOptions.web.appId.isNotEmpty &&
        DefaultFirebaseOptions.web.projectId.isNotEmpty &&
        DefaultFirebaseOptions.web.messagingSenderId.isNotEmpty;

    if (kIsWeb && hasWebFirebaseConfig) {
      try {
        debugPrint(
          '[BackendRuntime] Web Firebase options: '
              'projectId=${DefaultFirebaseOptions.web.projectId}, '
              'appId=${DefaultFirebaseOptions.web.appId}, '
              'apiKey length=${DefaultFirebaseOptions.web.apiKey.length}',
        );

        final app = Firebase.apps.isEmpty
            ? await Firebase.initializeApp(
                options: FirebaseOptions(
                  apiKey: DefaultFirebaseOptions.web.apiKey,
                  appId: DefaultFirebaseOptions.web.appId,
                  messagingSenderId:
                      DefaultFirebaseOptions.web.messagingSenderId,
                  projectId: DefaultFirebaseOptions.web.projectId,
                  authDomain: DefaultFirebaseOptions.web.authDomain,
                ),
              )
            : Firebase.apps.first;

        firebaseInitialized = true;
        firebaseMessage = 'Firebase initialized for app ${app.name}.';

        debugPrint(
          '[BackendRuntime] Firebase initialized on web for ${app.name}.',
        );
      } catch (error, stackTrace) {
        firebaseInitialized = false;
        firebaseMessage = 'Firebase init failed: $error';

        debugPrint('[BackendRuntime] Firebase init failed on web: $error');
        debugPrint('$stackTrace');
      }
    } else if (kIsWeb) {
      firebaseMessage =
          'Firebase init skipped on web because required config values are missing.';

      debugPrint('[BackendRuntime] Firebase init skipped on web.');
    } else {
      firebaseMessage =
          'Firebase init skipped on non-web platforms because only web config exists.';

      debugPrint('[BackendRuntime] Firebase init skipped outside web.');
    }

    final authMode = firebaseInitialized
        ? BackendAuthMode.firebaseAuthFirestore
        : BackendAuthMode.localMock;

    _snapshot = BackendRuntimeSnapshot(
      authMode: authMode,
      cloudflareHostingDetected: cloudflareHostingDetected,
      firebaseConfiguredForWeb: hasWebFirebaseConfig,
      firebaseInitialized: firebaseInitialized,
      firebaseMessage: firebaseMessage,
    );

    debugPrint(
      '[BackendRuntime] Auth mode=${_snapshot.authModeLabel}, '
          'firebaseConfiguredForWeb=${_snapshot.firebaseConfiguredForWeb}, '
          'firebaseInitialized=${_snapshot.firebaseInitialized}, '
          'cloudflareHostingDetected=${_snapshot.cloudflareHostingDetected}.',
    );
  }

  bool get useFirebaseAuth {
    return _snapshot.authMode == BackendAuthMode.firebaseAuthFirestore;
  }
}
