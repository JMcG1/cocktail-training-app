import 'browser_app_recovery_stub.dart'
    if (dart.library.html) 'browser_app_recovery_web.dart'
    as browser_app_recovery;

class BrowserAppRecovery {
  const BrowserAppRecovery._();

  static Future<void> refreshApp() => browser_app_recovery.refreshApp();

  static Future<void> clearSavedAppData() =>
      browser_app_recovery.clearSavedAppData();

  static String diagnostics({
    required String buildLabel,
    required String runtimeMode,
    required bool isOnline,
  }) {
    return browser_app_recovery.diagnostics(
      buildLabel: buildLabel,
      runtimeMode: runtimeMode,
      isOnline: isOnline,
    );
  }
}
