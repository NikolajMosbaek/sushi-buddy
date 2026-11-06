#!/bin/bash
# Packages Sushi Buddy for Windows (x64 and arm64) into dist/*.zip.
# On Windows (Git Bash, as in the release workflow) the .exe gets the sushi icon and the
# app's name in its file details, so Task Manager says "Sushi Buddy". Elsewhere that would
# need Wine, so a package made on macOS or Linux keeps Electron's own icon and details.
set -euo pipefail
cd "$(dirname "$0")/.."

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) on_windows=1 ;;
  *) on_windows=0 ;;
esac
version=$(node -p "require('./package.json').version")
details=()
if [[ $on_windows == 1 ]]; then
  details=(
    --icon=icon.ico
    --app-copyright="Nikolaj Søgaard Simonsen"
    --win32metadata.ProductName="Sushi Buddy"
    --win32metadata.FileDescription="Sushi Buddy"
    --win32metadata.CompanyName="Nikolaj Søgaard Simonsen"
    --win32metadata.OriginalFilename="Sushi Buddy.exe"
  )
fi

rm -rf dist
for arch in x64 arm64; do
  # The app has no runtime dependencies, so node_modules (Electron and the
  # packager themselves) stays out entirely.
  npx electron-packager . "Sushi Buddy" \
    --platform=win32 --arch="$arch" --app-version="$version" \
    --out=dist --asar --overwrite ${details[@]+"${details[@]}"} \
    --ignore='^/(dist|scripts|node_modules|test)(/|$)' --ignore='^/(sync-assets\.js|icon\.ico|\.gitignore)$'
  # Every UI string is the app's own, so Chromium's other languages only add size.
  find "dist/Sushi Buddy-win32-$arch/locales" -name '*.pak' ! -name 'en-US.pak' -delete
  if command -v zip > /dev/null; then
    (cd dist && zip -qry -9 "Sushi-Buddy-windows-$arch.zip" "Sushi Buddy-win32-$arch")
  else
    (cd dist && 7z a -tzip -mx=9 -bso0 "Sushi-Buddy-windows-$arch.zip" "Sushi Buddy-win32-$arch")
  fi
done
ls -l dist/*.zip
