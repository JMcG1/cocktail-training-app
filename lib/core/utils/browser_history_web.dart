// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

typedef BrowserHistoryListener = void Function(String fragment);

final Set<BrowserHistoryListener> _listeners = <BrowserHistoryListener>{};
StreamSubscription<html.PopStateEvent>? _popStateSubscription;
int _sequence = 0;

String currentBrowserFragment() => Uri.base.fragment;

void primeBrowserHistory(String fragment) {
  final state = html.window.history.state;
  if (_isHistoryState(state) && state['primed'] == true) {
    return;
  }
  final target = _buildUrl(fragment);
  final replaceState = _historyState(fragment, primed: false);
  final pushState = _historyState(fragment, primed: true);
  html.window.history.replaceState(replaceState, html.document.title, target);
  html.window.history.pushState(pushState, html.document.title, target);
}

void pushBrowserFragment(String fragment) {
  final target = _buildUrl(fragment);
  html.window.history.pushState(
    _historyState(fragment, primed: true),
    html.document.title,
    target,
  );
}

void replaceBrowserFragment(String fragment) {
  final target = _buildUrl(fragment);
  html.window.history.replaceState(
    _historyState(fragment, primed: true),
    html.document.title,
    target,
  );
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

Map<String, Object> _historyState(String fragment, {required bool primed}) {
  _sequence += 1;
  return <String, Object>{
    'app': 'cocktail-training',
    'fragment': fragment,
    'primed': primed,
    'sequence': _sequence,
  };
}

bool _isHistoryState(Object? state) {
  return state is Map && state['app'] == 'cocktail-training';
}
