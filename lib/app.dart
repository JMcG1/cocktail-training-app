import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/config/app_environment.dart';
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
                      if (!kReleaseMode) ...[
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: SelectableText(
                            [
                              'Hostname: ${Uri.base.host}',
                              'APP_MODE: ${_environment.appMode.name}',
                              'Firebase hints present: ${_environment.hasAnyFirebaseHints}',
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
      'team access could not be loaded',
      'missing a venue assignment',
      'does not have access to a venue',
      'unknown role',
      'currently paused',
    ])) {
      return _StartupErrorDetails(category: 'access', summary: raw);
    }

    if (_containsAny(normalized, const [
      'training data',
      'cocktail list is not ready',
      'cocktail list was not available',
      'shared cocktail list',
    ])) {
      return _StartupErrorDetails(category: 'data', summary: raw);
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
      return _StartupErrorDetails(category: 'web-shell', summary: raw);
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
