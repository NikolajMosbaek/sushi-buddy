#!/bin/bash
# Packages Sushi Buddy for Windows (x64 and arm64) into dist/*.zip.
# Runs on macOS or Linux too: nothing edits the .exe, so no Wine is needed
# (which is also why the .exe keeps Electron's own icon when built off Windows).
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf dist
for arch in x64 arm64; do
  # The app has no runtime dependencies, so node_modules (Electron and the
  # packager themselves) stays out entirely.
  npx electron-packager . "Sushi Buddy" \
    --platform=win32 --arch="$arch" \
    --out=dist --asar --overwrite \
    --ignore='^/(dist|scripts|node_modules|test)(/|$)' --ignore='^/(sync-assets\.js|\.gitignore)$'
  # Every UI string is the app's own, so Chromium's other languages only add size.
  find "dist/Sushi Buddy-win32-$arch/locales" -name '*.pak' ! -name 'en-US.pak' -delete
  (cd dist && zip -qry -9 "Sushi-Buddy-windows-$arch.zip" "Sushi Buddy-win32-$arch")
done
ls -l dist/*.zip
