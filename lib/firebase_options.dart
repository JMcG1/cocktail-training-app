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

  static const String _rawApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _rawAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _rawMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _rawProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _rawAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String _rawStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

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

  static FirebaseOptions get web {
    final defineConfig = _normalizedWebDefineConfig;
    final useDefineConfig = _isCompleteWebDefineConfig(defineConfig);

    return FirebaseOptions(
      apiKey: useDefineConfig ? defineConfig.apiKey : _fallbackApiKey,
      appId: useDefineConfig ? defineConfig.appId : _fallbackAppId,
      messagingSenderId: useDefineConfig
          ? defineConfig.messagingSenderId
          : _fallbackMessagingSenderId,
      projectId: useDefineConfig ? defineConfig.projectId : _fallbackProjectId,
      authDomain: useDefineConfig
          ? defineConfig.authDomain
          : _fallbackAuthDomain,
      storageBucket: useDefineConfig
          ? defineConfig.storageBucket
          : _fallbackStorageBucket,
    );
  }

  static bool get isWebDefineOverrideInUse {
    return _isCompleteWebDefineConfig(_normalizedWebDefineConfig);
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

  static _WebDefineConfig get _normalizedWebDefineConfig => _WebDefineConfig(
    apiKey: _normalizedDefine(_rawApiKey, ''),
    appId: _normalizedDefine(_rawAppId, ''),
    messagingSenderId: _normalizedDefine(_rawMessagingSenderId, ''),
    projectId: _normalizedDefine(_rawProjectId, ''),
    authDomain: _normalizedDefine(_rawAuthDomain, ''),
    storageBucket: _normalizedDefine(_rawStorageBucket, ''),
  );

  static bool _isCompleteWebDefineConfig(_WebDefineConfig config) {
    return config.apiKey.isNotEmpty &&
        config.appId.isNotEmpty &&
        config.messagingSenderId.isNotEmpty &&
        config.projectId.isNotEmpty &&
        config.authDomain.isNotEmpty &&
        config.storageBucket.isNotEmpty;
  }
}

class _WebDefineConfig {
  const _WebDefineConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.authDomain,
    required this.storageBucket,
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String authDomain;
  final String storageBucket;
}
