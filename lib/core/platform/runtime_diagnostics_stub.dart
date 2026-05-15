import 'runtime_diagnostics.dart';

RuntimeDiagnostics collectRuntimeDiagnosticsImpl() {
  return const RuntimeDiagnostics(
    browserLabel: 'non-web',
    platformLabel: 'non-web',
    userAgent: 'non-web',
    viewportLabel: 'n/a',
    localStorageAvailable: false,
    sessionStorageAvailable: false,
  );
}
