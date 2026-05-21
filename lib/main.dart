import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = AppEnvironment.fromDartDefines();
  developer.log(
    'App launch build=${environment.buildMarker} version=${environment.appVersionLabel} mode=${environment.appMode.name}',
    name: 'AppLaunch',
  );
  runApp(const StockVarianceCoachRoot());
}
