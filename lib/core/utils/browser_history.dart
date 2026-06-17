import 'browser_history_stub.dart'
    if (dart.library.html) 'browser_history_web.dart' as impl;

typedef BrowserHistoryListener = void Function(String fragment);

String currentBrowserFragment() => impl.currentBrowserFragment();

void pushBrowserFragment(String fragment) => impl.pushBrowserFragment(fragment);

void replaceBrowserFragment(String fragment) =>
    impl.replaceBrowserFragment(fragment);

void addBrowserHistoryListener(BrowserHistoryListener listener) =>
    impl.addBrowserHistoryListener(listener);

void removeBrowserHistoryListener(BrowserHistoryListener listener) =>
    impl.removeBrowserHistoryListener(listener);
