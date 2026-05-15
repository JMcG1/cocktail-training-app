#!/bin/bash
set -euo pipefail

app_mode="${APP_MODE:-}"
firebase_api_key="${FIREBASE_API_KEY:-}"
firebase_auth_domain="${FIREBASE_AUTH_DOMAIN:-}"
firebase_project_id="${FIREBASE_PROJECT_ID:-}"
firebase_storage_bucket="${FIREBASE_STORAGE_BUCKET:-}"
firebase_messaging_sender_id="${FIREBASE_MESSAGING_SENDER_ID:-}"
firebase_app_id="${FIREBASE_APP_ID:-}"
app_build="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "Cloudflare build diagnostics:"
echo "APP_MODE=${app_mode:-<empty>}"
echo "FIREBASE_PROJECT_ID=${firebase_project_id:-<empty>}"
echo "FIREBASE_AUTH_DOMAIN=${firebase_auth_domain:-<empty>}"
echo "FIREBASE_API_KEY length=${#firebase_api_key}"
echo "FIREBASE_APP_ID length=${#firebase_app_id}"
echo "GIT_COMMIT=${app_build}"

git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter clean
flutter pub get
rm -rf build/web

flutter build web --release \
"--web-renderer" "html" \
"--pwa-strategy=none" \
"--dart-define=APP_MODE=$app_mode" \
"--dart-define=APP_BUILD=$app_build" \
"--dart-define=WEB_RENDERER=html" \
"--dart-define=FIREBASE_API_KEY=$firebase_api_key" \
"--dart-define=FIREBASE_AUTH_DOMAIN=$firebase_auth_domain" \
"--dart-define=FIREBASE_PROJECT_ID=$firebase_project_id" \
"--dart-define=FIREBASE_STORAGE_BUCKET=$firebase_storage_bucket" \
"--dart-define=FIREBASE_MESSAGING_SENDER_ID=$firebase_messaging_sender_id" \
"--dart-define=FIREBASE_APP_ID=$firebase_app_id"
