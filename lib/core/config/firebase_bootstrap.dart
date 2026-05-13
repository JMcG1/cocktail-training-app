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
  });

  final bool initialized;
  final Object? error;
  final StackTrace? stackTrace;
  final String? appName;
  final String? projectId;
  final String? authDomain;
  final String? hostname;
  final bool usedDefaultFirebaseOptions;

  String? get errorSummary => error?.toString();

  String toDiagnosticSummary() {
    final buffer = StringBuffer()
      ..writeln('Firebase startup diagnostics:')
      ..writeln('  initialized: $initialized')
      ..writeln('  appName: ${appName ?? '<unknown>'}')
      ..writeln('  projectId: ${projectId ?? '<unknown>'}')
      ..writeln('  authDomain: ${authDomain ?? '<unknown>'}')
      ..writeln('  hostname: ${hostname ?? '<unknown>'}')
      ..writeln('  optionsSource: ${usedDefaultFirebaseOptions ? 'DefaultFirebaseOptions.currentPlatform' : 'dart-defines'}');
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
    if (options == null) {
      final result = FirebaseBootstrapResult(
        initialized: false,
        error: StateError(
          'No Firebase web options are available. Provide DefaultFirebaseOptions or valid dart-defines.',
        ),
        hostname: hostname,
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
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
      );
      return result;
    }

    try {
      await Firebase.initializeApp(
        options: options,
      );
      final app = Firebase.app();
      final result = FirebaseBootstrapResult(
        initialized: true,
        appName: app.name,
        projectId: app.options.projectId,
        authDomain: app.options.authDomain,
        hostname: hostname,
        usedDefaultFirebaseOptions: _isUsingDefaultOptions(environment),
      );
      developer.log(
        result.toDiagnosticSummary(),
        name: 'FirebaseBootstrap',
      );
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
      authDomain:
          environment.firebaseAuthDomain.isEmpty ? null : environment.firebaseAuthDomain,
      storageBucket:
          environment.firebaseStorageBucket.isEmpty ? null : environment.firebaseStorageBucket,
    );
  }

  static bool _isUsingDefaultOptions(AppEnvironment environment) {
    return kIsWeb || !environment.hasRequiredFirebaseConfig;
  }
}
