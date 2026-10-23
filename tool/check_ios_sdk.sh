#!/usr/bin/env bash
set -euo pipefail

sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
IFS=. read -r sdk_major sdk_minor _ <<< "$sdk_version"
if (( sdk_major < 27 || (sdk_major == 27 && ${sdk_minor:-0} < 1) )); then
  echo "Kazumi requires the iOS 27.1 SDK or later. Selected SDK: $sdk_version" >&2
  echo "Select Xcode 27.1 or later with DEVELOPER_DIR or xcode-select." >&2
  exit 1
fi
echo "Building with iOS SDK $sdk_version"
