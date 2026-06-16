import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

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
    if (!_isCompleteWebDefineConfig(defineConfig)) {
      throw StateError(
        'Firebase web config is missing. Set FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN, and FIREBASE_STORAGE_BUCKET in the build environment.',
      );
    }

    return FirebaseOptions(
      apiKey: defineConfig.apiKey,
      appId: defineConfig.appId,
      messagingSenderId: defineConfig.messagingSenderId,
      projectId: defineConfig.projectId,
      authDomain: defineConfig.authDomain,
      storageBucket: defineConfig.storageBucket,
    );
  }

  static bool get isWebDefineOverrideInUse {
    return _isCompleteWebDefineConfig(_normalizedWebDefineConfig);
  }

  static String webOptionsSource() {
    if (!kIsWeb) {
      return 'non-web';
    }
    return isWebDefineOverrideInUse
        ? 'DefaultFirebaseOptions.web (dart-defines)'
        : 'missing web firebase config';
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
