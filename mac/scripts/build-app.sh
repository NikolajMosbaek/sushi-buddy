#!/bin/bash
# Builds Sushi Buddy.app, installs it in ~/Applications and (re)starts it.
# --no-launch: install without starting it.
# --bundle-only: just build build/Sushi Buddy.app (what the release workflow does).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

app="build/Sushi Buddy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/SushiBuddy "$app/Contents/MacOS/"
# Sparkle, the updater: swift build links it from .build, so the app gets its own copy and is told where it is.
ditto .build/release/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/SushiBuddy"
cp ../Resources/* AppIcon.icns "$app/Contents/Resources/"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

if [[ "${1:-}" == "--bundle-only" ]]; then
  echo "Built $app"
  exit 0
fi

installed="$HOME/Applications/Sushi Buddy.app"
pkill -x SushiBuddy || true
mkdir -p "$HOME/Applications"
rm -rf "$installed"
ditto "$app" "$installed"
echo "Installed $installed"

if [[ "${1:-}" != "--no-launch" ]]; then
  open "$installed"
fi
