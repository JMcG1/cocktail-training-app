Future<void> refreshApp() async {}

Future<void> clearSavedAppData() async {}

String diagnostics({
  required String buildLabel,
  required String buildTimestamp,
  required String appVersionLabel,
  required String runtimeMode,
  required bool isOnline,
  String? catalogPathLabel,
}) {
  return [
    'build=$buildLabel',
    'buildTimestamp=$buildTimestamp',
    'version=$appVersionLabel',
    'mode=$runtimeMode',
    if ((catalogPathLabel ?? '').isNotEmpty) 'catalogPath=$catalogPathLabel',
    'online=$isOnline',
    'platform=non-web',
  ].join('\n');
}
