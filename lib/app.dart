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
    await controller.initialize(usingFirebase: bundle.usingFirebase);
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildMaterialApp(
            debugShowCheckedModeBanner: false,
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
                        _environment.appMode == AppMode.firebase
                            ? 'Firebase mode could not be started. Check the Firebase web config, allowed auth domain, and deployed Firestore rules, then try again.'
                            : 'The app could not start cleanly just now. Check the environment mode and configuration, then try again.',
                        textAlign: TextAlign.center,
                      ),
                      if (_environment.appMode == AppMode.firebase) ...[
                        const SizedBox(height: 12),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
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
          return _buildMaterialApp(
            debugShowCheckedModeBanner: false,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return AnimatedBuilder(
          animation: snapshot.data!,
          builder: (context, _) {
            return _buildMaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Stock Variance Coach',
              home: AppShell(controller: snapshot.data!),
            );
          },
        );
      },
    );
  }

  MaterialApp _buildMaterialApp({
    bool debugShowCheckedModeBanner = false,
    String? title,
    required Widget home,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      title: title,
      theme: buildAppTheme(),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (_environment.appMode != AppMode.firebase) {
          return content;
        }

        return Stack(
          children: [
            content,
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: _FirebaseStartupDiagnosticCard(
                  environment: _environment,
                ),
              ),
            ),
          ],
        );
      },
      home: home,
    );
  }
}

class _FirebaseStartupDiagnosticCard extends StatelessWidget {
  const _FirebaseStartupDiagnosticCard({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnostics = environment.firebaseStartupDiagnostics.entries.toList();

    return Opacity(
      opacity: 0.96,
      child: Card(
        elevation: 8,
        color: const Color(0xFF132238),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: theme.textTheme.bodySmall!.copyWith(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Firebase startup diagnostic',
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in diagnostics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('${entry.key}: ${entry.value}'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
