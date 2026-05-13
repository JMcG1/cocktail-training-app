import 'browser_connectivity_stub.dart'
    if (dart.library.html) 'browser_connectivity_web.dart' as browser_connectivity;

class BrowserConnectivity {
  const BrowserConnectivity._();

  static bool isOnline() => browser_connectivity.isOnline();
}
