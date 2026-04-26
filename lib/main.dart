import 'package:cocktail_training/app/app.dart';
import 'package:cocktail_training/services/backend_runtime_service.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackendRuntimeService.instance.initialize();
  runApp(const CocktailTrainingApp());
}
