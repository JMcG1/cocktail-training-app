// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'runtime_diagnostics.dart';

RuntimeDiagnostics collectRuntimeDiagnosticsImpl() {
  final navigator = html.window.navigator;
  final userAgent = navigator.userAgent;
  return RuntimeDiagnostics(
    browserLabel: _browserLabel(userAgent),
    platformLabel: navigator.platform ?? 'unknown',
    userAgent: userAgent,
    viewportLabel: '${html.window.innerWidth}x${html.window.innerHeight}',
    localStorageAvailable: _storageAvailable(() => html.window.localStorage),
    sessionStorageAvailable: _storageAvailable(() => html.window.sessionStorage),
    indexedDbAvailable: _storageAvailable(() => html.window.indexedDB),
  );
}

String _browserLabel(String userAgent) {
  final lower = userAgent.toLowerCase();
  if (lower.contains('firefox')) {
    return 'Firefox';
  }
  if (lower.contains('edg/')) {
    return 'Edge';
  }
  if (lower.contains('crios')) {
    return 'Chrome iOS';
  }
  if (lower.contains('chrome')) {
    return 'Chrome';
  }
  if (lower.contains('safari')) {
    return 'Safari';
  }
  return 'Unknown browser';
}

bool _storageAvailable(Object? Function() loader) {
  try {
    loader();
    return true;
  } catch (_) {
    return false;
  }
}
