enum AppMode { auto, demo, firebase }

class AppEnvironment {
  const AppEnvironment({
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseProjectId,
    required this.firebaseAuthDomain,
    required this.firebaseStorageBucket,
    required this.demoManagerEmail,
    required this.demoManagerPassword,
    required this.defaultVenueId,
    required this.appMode,
  });

  factory AppEnvironment.fromDartDefines() {
    return AppEnvironment(
      firebaseApiKey: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_API_KEY'),
      ),
      firebaseAppId: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_APP_ID'),
      ),
      firebaseMessagingSenderId: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      ),
      firebaseProjectId: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      ),
      firebaseAuthDomain: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      ),
      firebaseStorageBucket: _normalizeDefine(
        const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      ),
      demoManagerEmail: _normalizeDefine(
        const String.fromEnvironment(
          'DEMO_MANAGER_EMAIL',
          defaultValue: 'manager@venueflow.demo',
        ),
      ),
      demoManagerPassword: _normalizeDefine(
        const String.fromEnvironment(
          'DEMO_MANAGER_PASSWORD',
          defaultValue: 'coach123',
        ),
      ),
      defaultVenueId: _normalizeDefine(
        const String.fromEnvironment(
          'DEFAULT_VENUE_ID',
          defaultValue: 'demo-venue',
        ),
      ),
      appMode: _appModeFromString(
        _normalizeDefine(
          const String.fromEnvironment('APP_MODE', defaultValue: 'auto'),
        ),
      ),
    );
  }

  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseProjectId;
  final String firebaseAuthDomain;
  final String firebaseStorageBucket;
  final String demoManagerEmail;
  final String demoManagerPassword;
  final String defaultVenueId;
  final AppMode appMode;

  bool get hasFirebaseConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  bool get hasRequiredFirebaseConfig =>
      hasFirebaseConfig && firebaseAuthDomain.isNotEmpty;

  bool get hasAnyFirebaseHints =>
      hasRequiredFirebaseConfig ||
      firebaseStorageBucket.isNotEmpty ||
      firebaseAuthDomain.isNotEmpty ||
      firebaseProjectId.isNotEmpty;

  static AppMode _appModeFromString(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'demo':
        return AppMode.demo;
      case 'firebase':
        return AppMode.firebase;
      default:
        return AppMode.auto;
    }
  }

  static String _normalizeDefine(String raw, {String defaultValue = ''}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return defaultValue;
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
