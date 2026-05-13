import 'browser_storage_stub.dart'
    if (dart.library.html) 'browser_storage_web.dart' as browser_storage;

class BrowserStorage {
  const BrowserStorage._();

  static String? getString(String key) => browser_storage.getString(key);

  static void setString(String key, String value) => browser_storage.setString(key, value);

  static void remove(String key) => browser_storage.remove(key);
}
