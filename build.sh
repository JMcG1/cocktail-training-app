#!/bin/bash

git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter pub get

flutter build web --release \
--dart-define=APP_MODE=$APP_MODE \
--dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY \
--dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN \
--dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
--dart-define=FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET \
--dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID \
--dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID