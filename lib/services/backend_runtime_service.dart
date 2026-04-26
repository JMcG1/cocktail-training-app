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

    if (kIsWeb) {
      try {
        // Always initialise Firebase on web
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
        firebaseInitialized = false;
        firebaseMessage = 'Firebase init failed: $error';

        debugPrint('[BackendRuntime] Firebase init failed on web: $error');
        debugPrint('$stackTrace');
      }
    } else {
      firebaseMessage =
      'Firebase init skipped on non-web platforms (web-only config).';

      debugPrint('[BackendRuntime] Firebase init skipped outside web.');
    }

    /// 🔥 CRITICAL FIX:
    /// FORCE Firebase mode ON for web if init succeeded
    final authMode =
    (kIsWeb && firebaseInitialized)
        ? BackendAuthMode.firebaseAuthFirestore
        : BackendAuthMode.localMock;

    _snapshot = BackendRuntimeSnapshot(
      authMode: authMode,
      cloudflareHostingDetected: cloudflareHostingDetected,
      firebaseConfiguredForWeb: true,
      firebaseInitialized: firebaseInitialized,
      firebaseMessage: firebaseMessage,
    );

    debugPrint(
      '[BackendRuntime] Auth mode=${_snapshot.authModeLabel}, '
          'firebaseInitialized=${_snapshot.firebaseInitialized}, '
          'cloudflareHostingDetected=${_snapshot.cloudflareHostingDetected}.',
    );
  }

  /// 🔥 SECOND SAFETY NET (very important)
  bool get useFirebaseAuth {
    if (kIsWeb) return true; // FORCE for web
    return _snapshot.authMode == BackendAuthMode.firebaseAuthFirestore;
  }
}