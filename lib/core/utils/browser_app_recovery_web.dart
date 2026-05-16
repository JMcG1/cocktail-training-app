// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<void> refreshApp() async {
  await _clearLegacyFlutterCaches();
  html.window.location.reload();
}

Future<void> clearSavedAppData() async {
  try {
    html.window.localStorage.clear();
  } catch (_) {}
  try {
    html.window.sessionStorage.clear();
  } catch (_) {}
  await _clearLegacyFlutterCaches();
  final location = html.window.location;
  final queryParameters = Map<String, String>.from(Uri.base.queryParameters);
  queryParameters['_cb'] = DateTime.now().millisecondsSinceEpoch.toString();
  final refreshed = Uri(
    scheme: location.protocol.replaceAll(':', ''),
    host: location.hostname,
    port: location.port.isNotEmpty ? int.tryParse(location.port) : null,
    path: location.pathname,
    queryParameters: queryParameters,
    fragment: location.hash.replaceFirst('#', ''),
  );
  html.window.location.assign(refreshed.toString());
}

String diagnostics({
  required String buildLabel,
  required String runtimeMode,
  required bool isOnline,
}) {
  return [
    'build=$buildLabel',
    'mode=$runtimeMode',
    'online=$isOnline',
    'host=${html.window.location.host}',
    'path=${html.window.location.pathname}',
    'userAgent=${html.window.navigator.userAgent}',
    'viewport=${html.window.innerWidth}x${html.window.innerHeight}',
    'localStorage=${_storageAvailable(() => html.window.localStorage)}',
    'sessionStorage=${_storageAvailable(() => html.window.sessionStorage)}',
  ].join('\n');
}

Future<void> _clearLegacyFlutterCaches() async {
  try {
    final serviceWorker = html.window.navigator.serviceWorker;
    if (serviceWorker != null) {
      final registrations = await serviceWorker.getRegistrations();
      for (final registration in registrations) {
        await registration.unregister();
      }
    }
  } catch (_) {}

  try {
    final cacheStorage = html.window.caches;
    if (cacheStorage != null) {
      final cacheKeys = await cacheStorage.keys();
      for (final key in cacheKeys) {
        await cacheStorage.delete(key);
      }
    }
  } catch (_) {}
}

bool _storageAvailable(Object? Function() getter) {
  try {
    return getter() != null;
  } catch (_) {
    return false;
  }
}
