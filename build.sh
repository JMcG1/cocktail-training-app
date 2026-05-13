#!/bin/bash

git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter pub get

flutter build web --release \
--dart-define=APP_MODE=firebase \
--dart-define=FIREBASE_API_KEY=AIzaSyDdMoqAeDkgKwWK-uzLGgK4pliTKjhTH8I \
--dart-define=FIREBASE_AUTH_DOMAIN=bar-variance-training.firebaseapp.com \
--dart-define=FIREBASE_PROJECT_ID=bar-variance-training \
--dart-define=FIREBASE_STORAGE_BUCKET=bar-variance-training.firebasestorage.app \
--dart-define=FIREBASE_MESSAGING_SENDER_ID=397301018369 \
--dart-define=FIREBASE_APP_ID=1:397301018369:web:1d3f51892cd5584988b500