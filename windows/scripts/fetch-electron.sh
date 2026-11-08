#!/bin/bash
# Downloads this Electron version's Windows zips into the folder given, through the GitHub API,
# and checks them against Electron's SHASUMS256.txt; package.sh uses them via ELECTRON_ZIP_DIR.
# The packager's own download (github.com/…/releases/download) answered 504 for hours on
# 8 Nov 2026 while the API served the same files. Needs gh, logged in or with GH_TOKEN.
set -euo pipefail
dir=$1
version=$(cd "$(dirname "$0")/.." && node -p "require('electron/package.json').version")

mkdir -p "$dir"
cd "$dir"
gh release download "v$version" --repo electron/electron --clobber --pattern SHASUMS256.txt \
  --pattern "electron-v$version-win32-x64.zip" --pattern "electron-v$version-win32-arm64.zip"
grep -E " \*electron-v$version-win32-(x64|arm64)\.zip$" SHASUMS256.txt > win32.sha256
sha256sum -c win32.sha256
