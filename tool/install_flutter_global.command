#!/usr/bin/env bash
# Run in the user's Terminal: install the official SDK for all local projects.
set -euo pipefail

sdk_version=3.50.0
archive_name="flutter_macos_arm64_${sdk_version}-stable.zip"
archive_sha256=ed2d08a3e3c023e84cbe9316d21bd88fda6ee9552f90c1eb4da41a07c170fb35
archive_path="$HOME/Downloads/$archive_name"
sdk_dir="$HOME/Developer/flutter"
timestamp="$(date +%Y%m%d-%H%M%S)"

case "${1:-}" in
  --dry-run)
    printf 'SDK: %s\nArchive: %s\nShell configuration: %s and %s\n' \
      "$sdk_dir" "$archive_path" "$HOME/.zprofile" "$HOME/.zshrc"
    echo 'Existing shell files will be backed up; no sudo is required.'
    exit 0
    ;;
  '') ;;
  *) echo 'Usage: install_flutter_global.command [--dry-run]' >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'This downloaded SDK is for Apple Silicon macOS.' >&2
  exit 1
fi

if [[ -e "$sdk_dir" || -L "$sdk_dir" ]]; then
  if [[ ! -x "$sdk_dir/bin/flutter" ]] ||
     ! "$sdk_dir/bin/flutter" --version --machine | /usr/bin/grep -Eq '"frameworkVersion": *"3\.50\.0"'; then
    echo "An existing, different SDK occupies $sdk_dir. Nothing was replaced." >&2
    exit 1
  fi
else
  if [[ ! -f "$archive_path" ]]; then
    echo "Missing official archive: $archive_path" >&2
    echo 'Download macOS arm64 Flutter 3.50.0 from https://docs.flutter.dev/install/archive' >&2
    exit 1
  fi
  echo 'Checking the already downloaded official archive...'
  actual_sha256="$(/usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{print $1}')"
  if [[ "$actual_sha256" != "$archive_sha256" ]]; then
    echo 'Archive differs from the verified download. Installation stopped.' >&2
    exit 1
  fi
  mkdir -p "$HOME/Developer"
  staging_dir="$(mktemp -d "$HOME/Developer/.flutter-install.XXXXXX")"
  /usr/bin/ditto -x -k "$archive_path" "$staging_dir"
  [[ -x "$staging_dir/flutter/bin/flutter" ]]
  mv "$staging_dir/flutter" "$sdk_dir"
  rmdir "$staging_dir"
fi

for shell_file in "$HOME/.zprofile" "$HOME/.zshrc"; do
  if ! /usr/bin/grep -Fq '# >>> shared Flutter SDK >>>' "$shell_file" 2>/dev/null; then
    if [[ -f "$shell_file" ]]; then
      cp -p "$shell_file" "$shell_file.before-flutter-$timestamp"
    fi
    cat >> "$shell_file" <<'SHELL_CONFIG'

# >>> shared Flutter SDK >>>
export FLUTTER_ROOT="$HOME/Developer/flutter"
case ":$PATH:" in
  *":$FLUTTER_ROOT/bin:"*) ;;
  *) export PATH="$FLUTTER_ROOT/bin:$PATH" ;;
esac
# <<< shared Flutter SDK <<<
SHELL_CONFIG
  fi
done

export PATH="$sdk_dir/bin:$PATH"
export FLUTTER_ROOT="$sdk_dir"
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
echo 'Checking SDK versions and preparing iOS/macOS artifacts...'
flutter --version
dart --version
flutter precache --ios --macos
flutter doctor -v
echo
echo 'Shared Flutter SDK setup finished. Open a new terminal and restart your IDE/Codex.'
echo "IDE Flutter SDK path: $sdk_dir"
echo 'Android SDK and CocoaPods are separate prerequisites reported by flutter doctor.'
