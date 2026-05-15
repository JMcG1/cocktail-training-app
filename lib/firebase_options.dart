import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const String _fallbackApiKey =
      'AIzaSyDdMoqAeDkgKwWK-uzLGgK4pliTKjhTH8I';
  static const String _fallbackAppId =
      '1:397301018369:web:1d3f51892cd5584988b500';
  static const String _fallbackMessagingSenderId = '397301018369';
  static const String _fallbackProjectId = 'bar-variance-training';
  static const String _fallbackAuthDomain =
      'bar-variance-training.firebaseapp.com';
  static const String _fallbackStorageBucket =
      'bar-variance-training.firebasestorage.app';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have only been configured for web in this project.',
        );
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for fuchsia.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_API_KEY'),
      _fallbackApiKey,
    ),
    appId: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_APP_ID'),
      _fallbackAppId,
    ),
    messagingSenderId: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      _fallbackMessagingSenderId,
    ),
    projectId: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      _fallbackProjectId,
    ),
    authDomain: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      _fallbackAuthDomain,
    ),
    storageBucket: _normalizedDefine(
      const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      _fallbackStorageBucket,
    ),
  );

  static bool get isWebDefineOverrideInUse {
    return const String.fromEnvironment('FIREBASE_API_KEY').trim().isNotEmpty &&
        const String.fromEnvironment('FIREBASE_APP_ID').trim().isNotEmpty &&
        const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        ).trim().isNotEmpty &&
        const String.fromEnvironment('FIREBASE_PROJECT_ID').trim().isNotEmpty &&
        const String.fromEnvironment(
          'FIREBASE_AUTH_DOMAIN',
        ).trim().isNotEmpty &&
        const String.fromEnvironment(
          'FIREBASE_STORAGE_BUCKET',
        ).trim().isNotEmpty;
  }

  static bool get hasBundledWebConfig => _fallbackApiKey.isNotEmpty;

  static String webOptionsSource() {
    if (!kIsWeb) {
      return 'non-web';
    }
    return isWebDefineOverrideInUse
        ? 'DefaultFirebaseOptions.web (dart-define override)'
        : 'DefaultFirebaseOptions.web (bundled fallback)';
  }

  static String _normalizedDefine(String raw, String fallback) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    final hasMatchingDoubleQuotes =
        trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"');
    final hasMatchingSingleQuotes =
        trimmed.length >= 2 && trimmed.startsWith("'") && trimmed.endsWith("'");
    if (hasMatchingDoubleQuotes || hasMatchingSingleQuotes) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }
}
