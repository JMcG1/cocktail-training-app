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
      firebaseApiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
      firebaseAppId: const String.fromEnvironment('FIREBASE_APP_ID'),
      firebaseMessagingSenderId: const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      firebaseProjectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      firebaseAuthDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      firebaseStorageBucket: const String.fromEnvironment(
        'FIREBASE_STORAGE_BUCKET',
      ),
      demoManagerEmail: const String.fromEnvironment(
        'DEMO_MANAGER_EMAIL',
        defaultValue: 'manager@venueflow.demo',
      ),
      demoManagerPassword: const String.fromEnvironment(
        'DEMO_MANAGER_PASSWORD',
        defaultValue: 'coach123',
      ),
      defaultVenueId: const String.fromEnvironment(
        'DEFAULT_VENUE_ID',
        defaultValue: 'demo-venue',
      ),
      appMode: _appModeFromString(
        const String.fromEnvironment('APP_MODE', defaultValue: 'auto'),
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
}
