// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String? getString(String key) => html.window.localStorage[key];

void setString(String key, String value) {
  html.window.localStorage[key] = value;
}

void remove(String key) {
  html.window.localStorage.remove(key);
}
