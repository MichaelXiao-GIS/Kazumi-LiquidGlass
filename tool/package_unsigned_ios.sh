#!/usr/bin/env bash
# Package the device build for re-signing by the installer.
set -euo pipefail
source_app=${1:?Expected a device .app}
output=${2:?Expected an output .ipa}
stage=$(mktemp -d "${TMPDIR:-/tmp}/kazumi-ipa.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
app="$stage/Payload/$(basename "$source_app")"
metadata=(--norsrc --noextattr --noqtn --noacl)
ditto "${metadata[@]}" "$source_app" "$app"
find "$app" -type f \( -name '._*' -o -name .DS_Store \) -delete

# Some prebuilt media frameworks arrive with read-only data-file permissions.
# Normalize only the executable named by each bundle, then seal the frameworks.
make_executable() {
  local binary
  binary=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Info.plist")
  chmod 755 "$1/$binary"
}
make_executable "$app"
for framework in "$app"/Frameworks/*.framework; do
  [[ -d "$framework" ]] || continue
  make_executable "$framework"
  codesign --force --sign - --timestamp=none "$framework"
done

ditto "${metadata[@]}" -c -k --keepParent "$stage/Payload" "$stage/package.ipa"
# Check what a ZIP-based signing tool will actually unpack.
unzip -q "$stage/package.ipa" -d "$stage/verify"
unpacked="$stage/verify/Payload/$(basename "$app")"
if [[ -n "$(find "$stage/verify" \( -name '._*' -o -name __MACOSX \) -print -quit)" ]]; then
  echo 'IPA contains macOS metadata' >&2
  exit 1
fi
for framework in "$unpacked"/Frameworks/*.framework; do
  [[ -d "$framework" ]] || continue
  codesign --verify --strict "$framework"
done
mv -f "$stage/package.ipa" "$output"
