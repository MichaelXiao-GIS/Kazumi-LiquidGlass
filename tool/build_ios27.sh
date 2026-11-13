#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tool/check_ios_sdk.sh

bash tool/flutterw pub get
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/kazumi-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
if [[ -n "${DANDANAPI_APPID:-}" || -n "${DANDANAPI_KEY:-}" ]]; then
  : "${DANDANAPI_APPID:?DANDANAPI_APPID and DANDANAPI_KEY must be set together}"
  : "${DANDANAPI_KEY:?DANDANAPI_APPID and DANDANAPI_KEY must be set together}"
  # Keep the two build-time values out of command output and process arguments.
  python3 -c 'import json, os, sys; json.dump({k: os.environ[k] for k in ("DANDANAPI_APPID", "DANDANAPI_KEY")}, sys.stdout)' > "$package_dir/defines.json"
  set -- "--dart-define-from-file=$package_dir/defines.json" "$@"
fi
bash tool/flutterw build ios --release --no-codesign "$@"
mkdir -p dist "$package_dir/Payload"
ditto build/ios/iphoneos/Runner.app "$package_dir/Payload/Runner.app"
ditto -c -k --keepParent "$package_dir/Payload" dist/Kazumi_iOS27_unsigned.ipa
(
  cd dist
  shasum -a 256 Kazumi_iOS27_unsigned.ipa > Kazumi_iOS27_unsigned.ipa.sha256
)
app_plist=build/ios/iphoneos/Runner.app/Info.plist
{
  echo 'Kazumi Liquid Glass — unsigned iOS build'
  echo "Built at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Source commit: $(git rev-parse HEAD)"
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo 'Source working tree: modified (not a clean tagged build)'
  else
    echo 'Source working tree: clean'
  fi
  for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion DTSDKName MinimumOSVersion; do
    echo "$key: $(/usr/libexec/PlistBuddy -c "Print :$key" "$app_plist")"
  done
  xcodebuild -version
  echo 'Signing: unsigned; re-sign before installing on a device.'
  echo "SHA-256: $(cut -d ' ' -f 1 dist/Kazumi_iOS27_unsigned.ipa.sha256)"
} > dist/BUILD_INFO.txt
echo "Unsigned package: dist/Kazumi_iOS27_unsigned.ipa"
