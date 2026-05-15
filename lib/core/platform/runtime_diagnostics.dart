import 'runtime_diagnostics_stub.dart'
    if (dart.library.html) 'runtime_diagnostics_web.dart';

class RuntimeDiagnostics {
  const RuntimeDiagnostics({
    required this.browserLabel,
    required this.platformLabel,
    required this.userAgent,
    required this.viewportLabel,
    required this.localStorageAvailable,
    required this.sessionStorageAvailable,
    required this.indexedDbAvailable,
  });

  final String browserLabel;
  final String platformLabel;
  final String userAgent;
  final String viewportLabel;
  final bool localStorageAvailable;
  final bool sessionStorageAvailable;
  final bool indexedDbAvailable;
}

RuntimeDiagnostics collectRuntimeDiagnostics() => collectRuntimeDiagnosticsImpl();
