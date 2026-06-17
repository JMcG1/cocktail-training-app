// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

typedef BrowserHistoryListener = void Function(String fragment);

final Set<BrowserHistoryListener> _listeners = <BrowserHistoryListener>{};
StreamSubscription<html.PopStateEvent>? _popStateSubscription;

String currentBrowserFragment() => Uri.base.fragment;

void pushBrowserFragment(String fragment) {
  final target = _buildUrl(fragment);
  html.window.history.pushState(null, html.document.title, target);
}

void replaceBrowserFragment(String fragment) {
  final target = _buildUrl(fragment);
  html.window.history.replaceState(null, html.document.title, target);
}

void addBrowserHistoryListener(BrowserHistoryListener listener) {
  _listeners.add(listener);
  _popStateSubscription ??= html.window.onPopState.listen((_) {
    final fragment = currentBrowserFragment();
    for (final callback in List<BrowserHistoryListener>.from(_listeners)) {
      callback(fragment);
    }
  });
}

void removeBrowserHistoryListener(BrowserHistoryListener listener) {
  _listeners.remove(listener);
  if (_listeners.isEmpty) {
    _popStateSubscription?.cancel();
    _popStateSubscription = null;
  }
}

String _buildUrl(String fragment) {
  final uri = Uri.base.replace(fragment: fragment.isEmpty ? null : fragment);
  return uri.toString();
}
