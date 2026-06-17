typedef BrowserHistoryListener = void Function(String fragment);

String currentBrowserFragment() => '';

void primeBrowserHistory(String fragment) {}

void pushBrowserFragment(String fragment) {}

void replaceBrowserFragment(String fragment) {}

void addBrowserHistoryListener(BrowserHistoryListener listener) {}

void removeBrowserHistoryListener(BrowserHistoryListener listener) {}
