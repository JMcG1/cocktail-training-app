#!/bin/bash
set -euo pipefail

app_mode="${APP_MODE:-}"
app_build="${APP_BUILD:-${CF_PAGES_COMMIT_SHA:-${GITHUB_SHA:-}}}"
firebase_api_key="${FIREBASE_API_KEY:-}"
firebase_auth_domain="${FIREBASE_AUTH_DOMAIN:-}"
firebase_project_id="${FIREBASE_PROJECT_ID:-}"
firebase_storage_bucket="${FIREBASE_STORAGE_BUCKET:-}"
firebase_messaging_sender_id="${FIREBASE_MESSAGING_SENDER_ID:-}"
firebase_app_id="${FIREBASE_APP_ID:-}"

if [ -z "$app_build" ]; then
  app_build="$(git rev-parse --short HEAD 2>/dev/null || date +%s)"
fi
app_build="$(printf '%s' "$app_build" | tr -cd '[:alnum:]' | cut -c1-12)"
if [ -z "$app_build" ]; then
  app_build="localbuild"
fi

echo "Cloudflare build diagnostics:"
echo "APP_MODE=${app_mode:-<empty>}"
echo "APP_BUILD=${app_build}"
echo "FIREBASE_PROJECT_ID=${firebase_project_id:-<empty>}"
echo "FIREBASE_AUTH_DOMAIN=${firebase_auth_domain:-<empty>}"
echo "FIREBASE_API_KEY length=${#firebase_api_key}"
echo "FIREBASE_APP_ID length=${#firebase_app_id}"

git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PATH:`pwd`/flutter/bin"

flutter config --enable-web
flutter clean
flutter pub get

flutter build web --release \
"--pwa-strategy=none" \
"--dart-define=APP_BUILD=$app_build" \
"--dart-define=APP_MODE=$app_mode" \
"--dart-define=FIREBASE_API_KEY=$firebase_api_key" \
"--dart-define=FIREBASE_AUTH_DOMAIN=$firebase_auth_domain" \
"--dart-define=FIREBASE_PROJECT_ID=$firebase_project_id" \
"--dart-define=FIREBASE_STORAGE_BUCKET=$firebase_storage_bucket" \
"--dart-define=FIREBASE_MESSAGING_SENDER_ID=$firebase_messaging_sender_id" \
"--dart-define=FIREBASE_APP_ID=$firebase_app_id"

python3 - <<PY
from pathlib import Path
import json

build_dir = Path("build/web")
build_label = "${app_build}"
bootstrap_path = build_dir / "flutter_bootstrap.js"
bootstrap_text = bootstrap_path.read_text(encoding="utf-8")
bootstrap_text = bootstrap_text.replace("__APP_BUILD__", build_label)
bootstrap_path.write_text(bootstrap_text, encoding="utf-8")

version_path = build_dir / "version.json"
version_path.write_text(
    json.dumps({"build": build_label}, indent=2) + "\n",
    encoding="utf-8",
)
PY

echo "Prepared no-service-worker web shell for build ${app_build}."
