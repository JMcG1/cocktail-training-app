import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      ..writeln(
        '  optionsSource: ${usedDefaultFirebaseOptions ? 'DefaultFirebaseOptions.currentPlatform' : 'dart-defines'}',
      );
    if (webOptionsSource != null) {
      buffer.writeln('  webOptionsSource: $webOptionsSource');
    }
    if (error != null) {
      buffer.writeln('  error: $error');
    }
    if (stackTrace != null) {
      buffer.writeln('  stackTrace: $stackTrace');
    }
    return buffer.toString().trimRight();
  }
}

class FirebaseBootstrap {
  static Future<FirebaseBootstrapResult> initializeIfPossible(
    AppEnvironment environment,
  ) async {
    final hostname = Uri.base.host;
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
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
        level: 1000,
        error: result.error,
      );
      return result;
    }

    if (Firebase.apps.isNotEmpty) {
      final app = Firebase.app();
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
      );
      developer.log(result.toDiagnosticSummary(), name: 'FirebaseBootstrap');
      return result;
    }

    try {
      await Firebase.initializeApp(options: options);
      final app = Firebase.app();
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
      );
      developer.log(result.toDiagnosticSummary(), name: 'FirebaseBootstrap');
      return result;
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
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      return result;
    }
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
}
