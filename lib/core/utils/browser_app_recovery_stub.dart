Future<void> refreshApp() async {}

Future<void> clearSavedAppData() async {}

String diagnostics({
  required String buildLabel,
  required String runtimeMode,
  required bool isOnline,
}) {
  return [
    'build=$buildLabel',
    'mode=$runtimeMode',
    'online=$isOnline',
    'platform=non-web',
  ].join('\n');
}
