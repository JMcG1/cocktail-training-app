#!/bin/bash
set -euo pipefail

app_mode="${APP_MODE:-}"
app_build="${APP_BUILD:-${CF_PAGES_COMMIT_SHA:-${GITHUB_SHA:-}}}"
app_build_time="${APP_BUILD_TIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
app_version_label="${APP_VERSION_LABEL:-web-json-catalog}"
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
echo "APP_BUILD_TIME=${app_build_time}"
echo "APP_VERSION_LABEL=${app_version_label}"
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
"--dart-define=APP_BUILD_TIME=$app_build_time" \
"--dart-define=APP_VERSION_LABEL=$app_version_label" \
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
import shutil
import sys

build_dir = Path("build/web")
web_dir = Path("web")
build_label = "${app_build}"
build_time = "${app_build_time}"
version_label = "${app_version_label}"
bootstrap_path = build_dir / "flutter_bootstrap.js"
bootstrap_text = bootstrap_path.read_text(encoding="utf-8")
bootstrap_text = bootstrap_text.replace("__APP_BUILD__", build_label)
bootstrap_text = bootstrap_text.replace("__APP_BUILD_TIME__", build_time)
bootstrap_text = bootstrap_text.replace("__APP_VERSION_LABEL__", version_label)
bootstrap_path.write_text(bootstrap_text, encoding="utf-8")

index_path = build_dir / "index.html"
index_text = index_path.read_text(encoding="utf-8")
index_text = index_text.replace("__APP_BUILD__", build_label)
index_text = index_text.replace("__APP_BUILD_TIME__", build_time)
index_text = index_text.replace("__APP_VERSION_LABEL__", version_label)
index_path.write_text(index_text, encoding="utf-8")

version_path = build_dir / "version.json"
version_path.write_text(
    json.dumps(
        {
            "build": build_label,
            "buildTime": build_time,
            "versionLabel": version_label,
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)

cleanup_worker_path = web_dir / "flutter_service_worker.js"
(build_dir / "flutter_service_worker.js").write_text(
    cleanup_worker_path.read_text(encoding="utf-8"),
    encoding="utf-8",
)

for sidecar_name in ("_headers", "_redirects"):
    sidecar_path = web_dir / sidecar_name
    if sidecar_path.exists():
        shutil.copyfile(sidecar_path, build_dir / sidecar_name)

errors = []

def require(condition, message):
    if not condition:
        errors.append(message)

final_index_text = index_path.read_text(encoding="utf-8")
final_bootstrap_text = bootstrap_path.read_text(encoding="utf-8")
headers_path = build_dir / "_headers"
service_worker_path = build_dir / "flutter_service_worker.js"
service_worker_text = service_worker_path.read_text(encoding="utf-8")
version_payload = json.loads(version_path.read_text(encoding="utf-8"))
cleanup_worker_text = cleanup_worker_path.read_text(encoding="utf-8")

require("__APP_BUILD__" not in final_index_text, "index.html still contains __APP_BUILD__ placeholder")
require("__APP_BUILD_TIME__" not in final_index_text, "index.html still contains __APP_BUILD_TIME__ placeholder")
require("__APP_VERSION_LABEL__" not in final_index_text, "index.html still contains __APP_VERSION_LABEL__ placeholder")
require("__APP_BUILD__" not in final_bootstrap_text, "flutter_bootstrap.js still contains __APP_BUILD__ placeholder")
require("__APP_BUILD_TIME__" not in final_bootstrap_text, "flutter_bootstrap.js still contains __APP_BUILD_TIME__ placeholder")
require("__APP_VERSION_LABEL__" not in final_bootstrap_text, "flutter_bootstrap.js still contains __APP_VERSION_LABEL__ placeholder")
require(build_label in final_index_text, "index.html does not contain the build marker")
require(build_label in final_bootstrap_text, "flutter_bootstrap.js does not contain the build marker")
require(headers_path.exists(), "build/web/_headers is missing")
require(version_payload.get("build") == build_label, "version.json build marker does not match the git/build label")
require(version_payload.get("buildTime") == build_time, "version.json buildTime does not match the stamped build time")
require(version_payload.get("versionLabel") == version_label, "version.json versionLabel does not match the stamped version label")
require(service_worker_text == cleanup_worker_text, "build/web/flutter_service_worker.js is not the cleanup worker")

service_worker_type = "cleanup-only" if service_worker_text == cleanup_worker_text else "unexpected"

print("Post-build verification summary:")
print(f"  build label: {build_label}")
print(f"  build time: {build_time}")
print(f"  version label: {version_label}")
print(f"  index.html marker found: {'yes' if build_label in final_index_text else 'no'}")
print(f"  flutter_bootstrap.js marker found: {'yes' if build_label in final_bootstrap_text else 'no'}")
print(f"  _headers copied: {'yes' if headers_path.exists() else 'no'}")
print(f"  version.json contents: {json.dumps(version_payload, sort_keys=True)}")
print(f"  service worker type: {service_worker_type}")

if errors:
    print("Post-build verification failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)
PY

echo "Prepared no-service-worker web shell for build ${app_build}."
