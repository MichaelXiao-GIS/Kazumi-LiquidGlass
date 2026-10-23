#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tool/check_ios_sdk.sh

flutter pub get
flutter build ios --release --no-codesign "$@"
mkdir -p dist
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/kazumi-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
ditto build/ios/iphoneos/Runner.app "$package_dir/Payload/Runner.app"
ditto -c -k --keepParent "$package_dir/Payload" dist/Kazumi_iOS27_unsigned.ipa
echo "Unsigned package: dist/Kazumi_iOS27_unsigned.ipa"
