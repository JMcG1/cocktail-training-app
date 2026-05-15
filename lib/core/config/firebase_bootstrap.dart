import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../platform/runtime_diagnostics.dart';
import 'app_environment.dart';
import '../../firebase_options.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({
    required this.initialized,
    this.error,
    this.stackTrace,
    this.appName,
    this.projectId,
    this.authDomain,
    this.hostname,
    this.usedDefaultFirebaseOptions = false,
    this.webOptionsSource,
    this.apiKeyPreview,
    this.apiKeyLength,
    this.isWeb = false,
    this.browserLabel,
    this.platformLabel,
    this.viewportLabel,
    this.localStorageAvailable,
    this.sessionStorageAvailable,
    this.indexedDbAvailable,
    this.authPersistenceMode,
    this.authPersistenceError,
    this.firestoreCacheMode,
    this.firestoreSettingsError,
  });

  final bool initialized;
  final Object? error;
  final StackTrace? stackTrace;
  final String? appName;
  final String? projectId;
  final String? authDomain;
  final String? hostname;
  final bool usedDefaultFirebaseOptions;
  final String? webOptionsSource;
  final String? apiKeyPreview;
  final int? apiKeyLength;
  final bool isWeb;
  final String? browserLabel;
  final String? platformLabel;
  final String? viewportLabel;
  final bool? localStorageAvailable;
  final bool? sessionStorageAvailable;
  final bool? indexedDbAvailable;
  final String? authPersistenceMode;
  final String? authPersistenceError;
  final String? firestoreCacheMode;
  final String? firestoreSettingsError;

  String? get errorSummary => error?.toString();

  String toDiagnosticSummary() {
    final buffer = StringBuffer()
      ..writeln('Firebase startup diagnostics:')
      ..writeln('  initialized: $initialized')
      ..writeln('  appName: ${appName ?? '<unknown>'}')
      ..writeln('  projectId: ${projectId ?? '<unknown>'}')
      ..writeln('  authDomain: ${authDomain ?? '<unknown>'}')
      ..writeln('  apiKeyPreview: ${apiKeyPreview ?? '<unknown>'}')
      ..writeln('  apiKeyLength: ${apiKeyLength ?? 0}')
      ..writeln('  isWeb: $isWeb')
      ..writeln('  hostname: ${hostname ?? '<unknown>'}')
      ..writeln('  browser: ${browserLabel ?? '<unknown>'}')
      ..writeln('  platform: ${platformLabel ?? '<unknown>'}')
      ..writeln('  viewport: ${viewportLabel ?? '<unknown>'}')
      ..writeln('  localStorage: ${localStorageAvailable ?? false}')
      ..writeln('  sessionStorage: ${sessionStorageAvailable ?? false}')
      ..writeln('  indexedDb: ${indexedDbAvailable ?? false}')
      ..writeln('  authPersistence: ${authPersistenceMode ?? '<unknown>'}')
      ..writeln('  firestoreCache: ${firestoreCacheMode ?? '<unknown>'}')
      ..writeln(
        '  optionsSource: ${usedDefaultFirebaseOptions ? 'DefaultFirebaseOptions.currentPlatform' : 'dart-defines'}',
      );
    if (webOptionsSource != null) {
      buffer.writeln('  webOptionsSource: $webOptionsSource');
    }
    if (error != null) {
      buffer.writeln('  error: $error');
    }
    if (authPersistenceError != null) {
      buffer.writeln('  authPersistenceError: $authPersistenceError');
    }
    if (firestoreSettingsError != null) {
      buffer.writeln('  firestoreSettingsError: $firestoreSettingsError');
    }
    if (stackTrace != null) {
      buffer.writeln('  stackTrace: $stackTrace');
    }
    return buffer.toString().trimRight();
  }
}

class FirebaseBootstrap {
  static FirebaseBootstrapResult? _latestResult;

  static FirebaseBootstrapResult? get latestResult => _latestResult;

  static Future<FirebaseBootstrapResult> initializeIfPossible(
    AppEnvironment environment,
  ) async {
    final hostname = Uri.base.host;
    final runtimeDiagnostics = collectRuntimeDiagnostics();
    final options = _resolveOptions(environment);
    final optionsSource = _describeOptionsSource(environment);
    final apiKeyPreview = _previewApiKey(options?.apiKey);
    final apiKeyLength = options?.apiKey.length;
    if (options == null) {
      final result = FirebaseBootstrapResult(
        initialized: false,
        error: StateError(
          'No Firebase web options are available. Provide DefaultFirebaseOptions or valid dart-defines.',
        ),
        hostname: hostname,
        webOptionsSource: optionsSource,
        apiKeyPreview: apiKeyPreview,
        apiKeyLength: apiKeyLength,
        isWeb: kIsWeb,
        browserLabel: runtimeDiagnostics.browserLabel,
        platformLabel: runtimeDiagnostics.platformLabel,
        viewportLabel: runtimeDiagnostics.viewportLabel,
        localStorageAvailable: runtimeDiagnostics.localStorageAvailable,
        sessionStorageAvailable: runtimeDiagnostics.sessionStorageAvailable,
        indexedDbAvailable: runtimeDiagnostics.indexedDbAvailable,
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
        level: 1000,
        error: result.error,
      );
      return _remember(result);
    }

    if (Firebase.apps.isNotEmpty) {
      final app = Firebase.app();
      final runtimeResult = await _configureWebRuntime();
      final result = FirebaseBootstrapResult(
        initialized: true,
        appName: app.name,
        projectId: app.options.projectId,
        authDomain: app.options.authDomain,
        hostname: hostname,
        usedDefaultFirebaseOptions: _isUsingDefaultOptions(environment),
        webOptionsSource: optionsSource,
        apiKeyPreview: _previewApiKey(app.options.apiKey),
        apiKeyLength: app.options.apiKey.length,
        isWeb: kIsWeb,
        browserLabel: runtimeDiagnostics.browserLabel,
        platformLabel: runtimeDiagnostics.platformLabel,
        viewportLabel: runtimeDiagnostics.viewportLabel,
        localStorageAvailable: runtimeDiagnostics.localStorageAvailable,
        sessionStorageAvailable: runtimeDiagnostics.sessionStorageAvailable,
        indexedDbAvailable: runtimeDiagnostics.indexedDbAvailable,
        authPersistenceMode: runtimeResult.authPersistenceMode,
        authPersistenceError: runtimeResult.authPersistenceError,
        firestoreCacheMode: runtimeResult.firestoreCacheMode,
        firestoreSettingsError: runtimeResult.firestoreSettingsError,
      );
      developer.log(result.toDiagnosticSummary(), name: 'FirebaseBootstrap');
      return _remember(result);
    }

    try {
      await Firebase.initializeApp(options: options);
      final app = Firebase.app();
      final runtimeResult = await _configureWebRuntime();
      final result = FirebaseBootstrapResult(
        initialized: true,
        appName: app.name,
        projectId: app.options.projectId,
        authDomain: app.options.authDomain,
        hostname: hostname,
        usedDefaultFirebaseOptions: _isUsingDefaultOptions(environment),
        webOptionsSource: optionsSource,
        apiKeyPreview: _previewApiKey(app.options.apiKey),
        apiKeyLength: app.options.apiKey.length,
        isWeb: kIsWeb,
        browserLabel: runtimeDiagnostics.browserLabel,
        platformLabel: runtimeDiagnostics.platformLabel,
        viewportLabel: runtimeDiagnostics.viewportLabel,
        localStorageAvailable: runtimeDiagnostics.localStorageAvailable,
        sessionStorageAvailable: runtimeDiagnostics.sessionStorageAvailable,
        indexedDbAvailable: runtimeDiagnostics.indexedDbAvailable,
        authPersistenceMode: runtimeResult.authPersistenceMode,
        authPersistenceError: runtimeResult.authPersistenceError,
        firestoreCacheMode: runtimeResult.firestoreCacheMode,
        firestoreSettingsError: runtimeResult.firestoreSettingsError,
      );
      developer.log(result.toDiagnosticSummary(), name: 'FirebaseBootstrap');
      return _remember(result);
    } catch (error, stackTrace) {
      final result = FirebaseBootstrapResult(
        initialized: false,
        error: error,
        stackTrace: stackTrace,
        appName: '[DEFAULT]',
        projectId: options.projectId,
        authDomain: options.authDomain,
        hostname: hostname,
        usedDefaultFirebaseOptions: _isUsingDefaultOptions(environment),
        webOptionsSource: optionsSource,
        apiKeyPreview: apiKeyPreview,
        apiKeyLength: apiKeyLength,
        isWeb: kIsWeb,
        browserLabel: runtimeDiagnostics.browserLabel,
        platformLabel: runtimeDiagnostics.platformLabel,
        viewportLabel: runtimeDiagnostics.viewportLabel,
        localStorageAvailable: runtimeDiagnostics.localStorageAvailable,
        sessionStorageAvailable: runtimeDiagnostics.sessionStorageAvailable,
        indexedDbAvailable: runtimeDiagnostics.indexedDbAvailable,
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      return _remember(result);
    }
  }

  static FirebaseBootstrapResult _remember(FirebaseBootstrapResult result) {
    _latestResult = result;
    return result;
  }

  static FirebaseOptions? _resolveOptions(AppEnvironment environment) {
    if (kIsWeb) {
      return DefaultFirebaseOptions.currentPlatform;
    }
    if (!environment.hasRequiredFirebaseConfig) {
      return null;
    }
    return FirebaseOptions(
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
    );
  }

  static bool _isUsingDefaultOptions(AppEnvironment environment) {
    return kIsWeb || !environment.hasRequiredFirebaseConfig;
  }

  static String _describeOptionsSource(AppEnvironment environment) {
    if (kIsWeb) {
      return DefaultFirebaseOptions.webOptionsSource();
    }
    return environment.hasRequiredFirebaseConfig ? 'dart-defines' : 'none';
  }

  static String _previewApiKey(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) {
      return '<empty>';
    }
    return apiKey.substring(0, apiKey.length >= 8 ? 8 : apiKey.length);
  }

  static Future<_FirebaseWebRuntimeResult> _configureWebRuntime() async {
    if (!kIsWeb) {
      return const _FirebaseWebRuntimeResult(
        authPersistenceMode: 'not-web',
        firestoreCacheMode: 'native',
      );
    }

    final authRuntime = await _configureWebAuthPersistence();
    final firestoreRuntime = _configureWebFirestoreSettings();
    return _FirebaseWebRuntimeResult(
      authPersistenceMode: authRuntime.mode,
      authPersistenceError: authRuntime.error,
      firestoreCacheMode: firestoreRuntime.mode,
      firestoreSettingsError: firestoreRuntime.error,
    );
  }

  static Future<_AuthPersistenceRuntimeResult>
  _configureWebAuthPersistence() async {
    final auth = firebase_auth.FirebaseAuth.instance;
    try {
      await auth.setPersistence(firebase_auth.Persistence.LOCAL);
      developer.log(
        'Firebase Auth persistence set to LOCAL.',
        name: 'FirebaseBootstrap',
      );
      return const _AuthPersistenceRuntimeResult(mode: 'local');
    } catch (localError, localStackTrace) {
      developer.log(
        'Firebase Auth LOCAL persistence unavailable. Falling back to SESSION.',
        name: 'FirebaseBootstrap',
        level: 900,
        error: localError,
        stackTrace: localStackTrace,
      );
      try {
        await auth.setPersistence(firebase_auth.Persistence.SESSION);
        developer.log(
          'Firebase Auth persistence set to SESSION.',
          name: 'FirebaseBootstrap',
          level: 900,
        );
        return _AuthPersistenceRuntimeResult(
          mode: 'session',
          error: localError.toString(),
        );
      } catch (sessionError, sessionStackTrace) {
        developer.log(
          'Firebase Auth SESSION persistence unavailable. Falling back to NONE.',
          name: 'FirebaseBootstrap',
          level: 900,
          error: sessionError,
          stackTrace: sessionStackTrace,
        );
        try {
          await auth.setPersistence(firebase_auth.Persistence.NONE);
          developer.log(
            'Firebase Auth persistence set to NONE.',
            name: 'FirebaseBootstrap',
            level: 900,
          );
          return _AuthPersistenceRuntimeResult(
            mode: 'none',
            error:
                'local=${localError.toString()}; session=${sessionError.toString()}',
          );
        } catch (noneError, noneStackTrace) {
          developer.log(
            'Firebase Auth persistence configuration failed for LOCAL, SESSION, and NONE.',
            name: 'FirebaseBootstrap',
            level: 1000,
            error: noneError,
            stackTrace: noneStackTrace,
          );
          return _AuthPersistenceRuntimeResult(
            mode: 'unconfigured',
            error:
                'local=${localError.toString()}; session=${sessionError.toString()}; none=${noneError.toString()}',
          );
        }
      }
    }
  }

  static _FirestoreRuntimeResult _configureWebFirestoreSettings() {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        webExperimentalAutoDetectLongPolling: true,
      );
      developer.log(
        'Firestore web settings applied with memory cache and auto-detect long polling.',
        name: 'FirebaseBootstrap',
      );
      return const _FirestoreRuntimeResult(
        mode: 'memory-cache + auto-detect-long-polling',
      );
    } catch (error, stackTrace) {
      developer.log(
        'Firestore web settings could not be applied.',
        name: 'FirebaseBootstrap',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      return _FirestoreRuntimeResult(
        mode: 'default',
        error: error.toString(),
      );
    }
  }
}

class _FirebaseWebRuntimeResult {
  const _FirebaseWebRuntimeResult({
    required this.authPersistenceMode,
    required this.firestoreCacheMode,
    this.authPersistenceError,
    this.firestoreSettingsError,
  });

  final String authPersistenceMode;
  final String? authPersistenceError;
  final String firestoreCacheMode;
  final String? firestoreSettingsError;
}

class _AuthPersistenceRuntimeResult {
  const _AuthPersistenceRuntimeResult({required this.mode, this.error});

  final String mode;
  final String? error;
}

class _FirestoreRuntimeResult {
  const _FirestoreRuntimeResult({required this.mode, this.error});

  final String mode;
  final String? error;
}
