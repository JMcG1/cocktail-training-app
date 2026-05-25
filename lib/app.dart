import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/config/app_environment.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/bundled_cocktail_catalog_loader.dart';
import 'data/repositories/repository_factory.dart';
import 'presentation/controllers/app_controller.dart';
import 'presentation/screens/app_shell.dart';

class StockVarianceCoachRoot extends StatefulWidget {
  const StockVarianceCoachRoot({super.key});

  @override
  State<StockVarianceCoachRoot> createState() => _StockVarianceCoachRootState();
}

class _StockVarianceCoachRootState extends State<StockVarianceCoachRoot> {
  late final AppEnvironment _environment = AppEnvironment.fromDartDefines();
  late final Future<AppController> _controllerFuture = _buildController();

  Future<AppController> _buildController() async {
    final bundle = await RepositoryFactory.create(_environment);
    final controller = AppController(
      authRepository: bundle.authRepository,
      trainingRepository: bundle.trainingRepository,
      environment: _environment,
    );
    try {
      await controller.initialize(usingFirebase: bundle.usingFirebase);
    } catch (error, stackTrace) {
      developer.log(
        'Controller initialize failed after app bootstrap',
        name: 'AppStartup',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      controller.recordNonBlockingStartupIssue(error);
    }
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final startupError = _StartupErrorDetails.from(snapshot.error!);
          final errorText = startupError.summary;
          final stackTraceText = snapshot.stackTrace?.toString() ?? '';
          final bundledDiagnostics = BundledCocktailCatalogLoader.lastDiagnostics;
          final firebaseBootstrap = FirebaseBootstrap.lastResult;
          developer.log(
            'Startup failed [${startupError.category}]: $errorText',
            name: 'AppStartup',
            level: 1000,
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'Unable to start the app',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        startupError.friendlyMessage(_environment.appMode),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      _BuildMarkerCard(
                        buildMarker: _environment.buildMarker,
                        appVersionLabel: _environment.appVersionLabel,
                        runtimeModeLabel: _environment.appMode.name,
                        catalogPathLabel: 'Library/Study direct JSON path active',
                        bundledDiagnostics: bundledDiagnostics,
                        startupError: startupError,
                        firebaseBootstrap: firebaseBootstrap,
                        errorText: errorText,
                        stackTraceText: kReleaseMode ? null : stackTraceText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Build ${_environment.buildMarker}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _environment.appVersionLabel,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return AnimatedBuilder(
          animation: snapshot.data!,
          builder: (context, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Cocktail Training',
              theme: buildAppTheme(),
              home: AppShell(controller: snapshot.data!),
            );
          },
        );
      },
    );
  }
}

class _StartupErrorDetails {
  const _StartupErrorDetails({
    required this.category,
    required this.summary,
    required this.firebaseInitializeFailed,
  });

  factory _StartupErrorDetails.from(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final normalized = raw.toLowerCase();

    if (_containsAny(normalized, const [
      'team access could not be loaded',
      'missing a venue assignment',
      'does not have access to a venue',
      'unknown role',
      'currently paused',
    ])) {
      return _StartupErrorDetails(
        category: 'access',
        summary: raw,
        firebaseInitializeFailed: false,
      );
    }

    if (_containsAny(normalized, const [
      'training data',
      'cocktail list is not ready',
      'cocktail list was not available',
      'shared cocktail list',
    ])) {
      return _StartupErrorDetails(
        category: 'data',
        summary: raw,
        firebaseInitializeFailed: false,
      );
    }

    if (_containsAny(normalized, const [
      'service worker',
      'serviceworker',
      'localstorage',
      'sessionstorage',
      'securityerror',
      'version.json',
      'cache storage',
      'flutter bootstrap',
      'main.dart.js',
      'flutter.js',
    ])) {
      return _StartupErrorDetails(
        category: 'web-shell',
        summary: raw,
        firebaseInitializeFailed: false,
      );
    }

    if (_containsAny(normalized, const [
      'app_mode is set to firebase',
      'firebase could not be initialized',
      'initializeapp',
      'defaultfirebaseoptions',
      'firebaseoptions',
      'api-key-not-valid',
      'firebase api key',
      'auth domain',
      'projectid=',
    ])) {
      return _StartupErrorDetails(
        category: 'firebase',
        summary: raw,
        firebaseInitializeFailed: true,
      );
    }

    if (_containsAny(normalized, const [
      'googlefonts',
      '.ttf',
      'unable to load asset',
      'unable to load font asset',
      'application assets',
      'font family',
    ])) {
      return _StartupErrorDetails(
        category: 'assets',
        summary: raw,
        firebaseInitializeFailed: false,
      );
    }

    return _StartupErrorDetails(
      category: 'startup',
      summary: raw,
      firebaseInitializeFailed: false,
    );
  }

  final String category;
  final String summary;
  final bool firebaseInitializeFailed;

  String friendlyMessage(AppMode appMode) {
    switch (category) {
      case 'access':
        return 'You’re signed in, but your team access could not be loaded.';
      case 'data':
        return 'We couldn’t connect to the training data. Please refresh and try again.';
      case 'web-shell':
        return 'The latest web app files could not be loaded cleanly. Try refreshing so the newest build can be picked up.';
      case 'firebase':
        return appMode == AppMode.firebase
            ? 'We couldn’t start the app just now. Please refresh and try again.'
            : 'The app could not start cleanly because a Firebase service failed to initialize.';
      case 'assets':
        return 'The app could not load one of its required bundled assets. Check the deployed web build and try again.';
      default:
        return 'The app could not start cleanly just now. Check the deployed build and startup configuration, then try again.';
    }
  }

  static bool _containsAny(String input, List<String> needles) {
    for (final needle in needles) {
      if (input.contains(needle)) {
        return true;
      }
    }
    return false;
  }
}

class _BuildMarkerCard extends StatelessWidget {
  const _BuildMarkerCard({
    required this.buildMarker,
    required this.appVersionLabel,
    required this.runtimeModeLabel,
    required this.catalogPathLabel,
    required this.bundledDiagnostics,
    required this.startupError,
    required this.firebaseBootstrap,
    required this.errorText,
    this.stackTraceText,
  });

  final String buildMarker;
  final String appVersionLabel;
  final String runtimeModeLabel;
  final String catalogPathLabel;
  final BundledCatalogDiagnostics bundledDiagnostics;
  final _StartupErrorDetails startupError;
  final FirebaseBootstrapResult? firebaseBootstrap;
  final String errorText;
  final String? stackTraceText;

  @override
  Widget build(BuildContext context) {
    final firebaseStatus = firebaseBootstrap == null
        ? 'not-attempted'
        : firebaseBootstrap!.initialized
        ? 'success'
        : 'failed';
    final catalogStatus = bundledDiagnostics.loaded
        ? 'loaded'
        : bundledDiagnostics.lastError == null
        ? 'not-yet-loaded'
        : 'failed';
    final details = <String>[
      'Build: $buildMarker',
      'Version: $appVersionLabel',
      'Runtime: $runtimeModeLabel',
      'Catalog path: $catalogPathLabel',
      'Firebase.initializeApp: $firebaseStatus',
      'Firebase init failed: ${startupError.firebaseInitializeFailed}',
      'Error type: ${startupError.category}',
      'Bundled cocktails: $catalogStatus',
      'Cocktail count: ${bundledDiagnostics.cocktailCount}',
      'Batch count: ${bundledDiagnostics.batchCount}',
      'First cocktail: ${bundledDiagnostics.firstCocktailName ?? '<none>'}',
      'Asset source: ${bundledDiagnostics.source}',
      if (bundledDiagnostics.attemptedPaths.isNotEmpty)
        'Asset paths: ${bundledDiagnostics.attemptedPaths.join(' | ')}',
      if (bundledDiagnostics.lastError != null)
        'Catalog error: ${bundledDiagnostics.lastError}',
      'Safe error: $errorText',
      if (stackTraceText != null && stackTraceText!.isNotEmpty)
        'Stack trace:\n$stackTraceText',
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            details.join('\n'),
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );
  }
}
