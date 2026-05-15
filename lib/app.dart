import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/config/app_environment.dart';
import 'core/platform/runtime_diagnostics.dart';
import 'core/theme/app_theme.dart';
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
    await controller.initialize(usingFirebase: bundle.usingFirebase);
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
          final diagnostics = collectRuntimeDiagnostics();
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
                      const SizedBox(height: 12),
                      Text(
                        'Build ${_environment.appBuildLabel} • ${Uri.base.host}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!kReleaseMode) ...[
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: SelectableText(
                            [
                              'Hostname: ${Uri.base.host}',
                              'Build: ${_environment.appBuildLabel}',
                              'APP_MODE: ${_environment.appMode.name}',
                              'Firebase hints present: ${_environment.hasAnyFirebaseHints}',
                              'Project ID: ${_environment.firebaseProjectId.isEmpty ? '<empty>' : _environment.firebaseProjectId}',
                              'Auth domain: ${_environment.firebaseAuthDomain.isEmpty ? '<empty>' : _environment.firebaseAuthDomain}',
                              'Browser: ${diagnostics.browserLabel}',
                              'Platform: ${diagnostics.platformLabel}',
                              'Viewport: ${diagnostics.viewportLabel}',
                              'localStorage: ${diagnostics.localStorageAvailable}',
                              'sessionStorage: ${diagnostics.sessionStorageAvailable}',
                              'User agent: ${diagnostics.userAgent}',
                              'Error category: ${startupError.category}',
                              'Error: $errorText',
                              if (stackTraceText.isNotEmpty)
                                'Stack trace:\n$stackTraceText',
                            ].join('\n'),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
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
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return AnimatedBuilder(
          animation: snapshot.data!,
          builder: (context, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Stock Variance Coach',
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
  const _StartupErrorDetails({required this.category, required this.summary});

  factory _StartupErrorDetails.from(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    final normalized = raw.toLowerCase();

    if (_containsAny(normalized, const [
      'service worker',
      'cache',
      'main.dart.js',
      'flutter_bootstrap',
      'securityerror',
      'failed to fetch dynamically imported module',
      'storage',
      'indexeddb',
      'localstorage',
      'sessionstorage',
    ])) {
      return _StartupErrorDetails(category: 'web-runtime', summary: raw);
    }

    if (_containsAny(normalized, const [
      'firebase',
      'firestore',
      'auth/',
      'permission-denied',
      'defaultfirebaseoptions',
      'firebaseoptions',
    ])) {
      return _StartupErrorDetails(category: 'firebase', summary: raw);
    }

    if (_containsAny(normalized, const [
      'googlefonts',
      '.ttf',
      'unable to load asset',
      'unable to load font asset',
      'application assets',
      'font family',
    ])) {
      return _StartupErrorDetails(category: 'assets', summary: raw);
    }

    return _StartupErrorDetails(category: 'startup', summary: raw);
  }

  final String category;
  final String summary;

  String friendlyMessage(AppMode appMode) {
    switch (category) {
      case 'web-runtime':
        return 'The web app could not start cleanly on this browser. Refresh the page, clear the site data if needed, and make sure the latest deployment has loaded.';
      case 'firebase':
        return appMode == AppMode.firebase
            ? 'Firebase mode could not be started. Check the Firebase web config, allowed auth domain, and deployed Firestore rules, then try again.'
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
