import 'dart:io';

Future<String?> tryLoadAssetTextFromFileSystem(String assetKey) async {
  final directFile = File(assetKey);
  if (await directFile.exists()) {
    return directFile.readAsString();
  }

  final normalizedKey = assetKey.replaceAll('/', Platform.pathSeparator);
  final relativeFile = File(normalizedKey);
  if (await relativeFile.exists()) {
    return relativeFile.readAsString();
  }

  final assetFile = File('assets${Platform.pathSeparator}$normalizedKey');
  if (await assetFile.exists()) {
    return assetFile.readAsString();
  }

  return null;
}
