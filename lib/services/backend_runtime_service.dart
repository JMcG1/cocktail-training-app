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

    var firebaseInitialized = false;
    String? firebaseMessage;

    if (kIsWeb) {
      try {
        final app = Firebase.apps.isNotEmpty
            ? Firebase.app()
            : await Firebase.initializeApp(
                options: DefaultFirebaseOptions.currentPlatform,
              );
        firebaseInitialized = true;
        firebaseMessage = 'Firebase initialized for app ${app.name}.';
        debugPrint(
          '[BackendRuntime] Firebase initialized on web for ${app.name}.',
        );
      } catch (error, stackTrace) {
        firebaseMessage = 'Firebase init failed: $error';
        debugPrint('[BackendRuntime] Firebase init failed on web: $error');
        debugPrint('$stackTrace');
      }
    } else {
      firebaseMessage =
          'Firebase init skipped on non-web platforms: only web config exists.';
      debugPrint('[BackendRuntime] Firebase init skipped outside web.');
    }

    _snapshot = BackendRuntimeSnapshot(
      authMode: firebaseInitialized
          ? BackendAuthMode.firebaseAuthFirestore
          : BackendAuthMode.localMock,
      cloudflareHostingDetected: cloudflareHostingDetected,
      firebaseConfiguredForWeb: true,
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

  bool get useFirebaseAuth =>
      _snapshot.authMode == BackendAuthMode.firebaseAuthFirestore;
}
