import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'asset_text_loader_stub.dart'
    if (dart.library.io) 'asset_text_loader_io.dart' as file_loader;

Future<String> loadBundledAssetText(
  String assetKey, {
  required String logName,
}) async {
  developer.log('Asset load start asset=$assetKey', name: logName);
  try {
    final text = await rootBundle.loadString(assetKey);
    developer.log(
      'Asset load success asset=$assetKey source=rootBundle chars=${text.length}',
      name: logName,
    );
    return text;
  } catch (error, stackTrace) {
    final fileText = await file_loader.tryLoadAssetTextFromFileSystem(assetKey);
    if (fileText != null) {
      developer.log(
        'Asset load success asset=$assetKey source=filesystem chars=${fileText.length}',
        name: logName,
      );
      return fileText;
    }
    developer.log(
      'Asset load via rootBundle failed asset=$assetKey',
      name: logName,
      level: _isBindingInitializationError(error) ? 800 : 1000,
      error: error,
      stackTrace: _isBindingInitializationError(error) ? null : stackTrace,
    );
    if (!kIsWeb) {
      rethrow;
    }
  }

  final webPath = '/assets/$assetKey';
  try {
    developer.log(
      'Asset web fallback start asset=$assetKey url=$webPath',
      name: logName,
    );
    final text = await NetworkAssetBundle(Uri.base).loadString(webPath);
    developer.log(
      'Asset web fallback success asset=$assetKey source=$webPath chars=${text.length}',
      name: logName,
    );
    return text;
  } catch (error, stackTrace) {
    developer.log(
      'Asset web fallback failed asset=$assetKey url=$webPath',
      name: logName,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

bool _isBindingInitializationError(Object error) {
  return error.toString().contains('Binding has not yet been initialized');
}
