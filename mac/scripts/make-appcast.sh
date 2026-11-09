#!/bin/bash
# Writes appcast.xml next to the Mac zip: Sparkle's update feed, with this version, its download
# URL on this version's GitHub release, its EdDSA signature and, when What's New has a list for
# exactly this version, those highlights for the update window.
#
# The release workflow passes the private key in SPARKLE_PRIVATE_KEY (a repository secret); without
# it the key comes from this Mac's keychain, where generate_keys saved it (account sushi-buddy),
# and macOS asks once whether generate_appcast may use it.
#
# Usage: make-appcast.sh path/to/Sushi-Buddy-macOS-arm64.zip
set -euo pipefail
zip="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mac="$(cd "$(dirname "$0")/.." && pwd)"
bin="$mac/.build/artifacts/sparkle/Sparkle/bin"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$mac/Info.plist")
# The tag is the full version (v1.6.0 for the Mac's 1.6); the release workflow checks Windows' matches it.
tag="v$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$mac/../windows/package.json")"
repository="https://github.com/NikolajMosbaek/sushi-buddy"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$zip" "$work/"
python3 -I - "$mac/../Resources/whats-new.json" "$version" "$work/$(basename "${zip%.zip}").html" <<'EOF'
import html, json, sys
notes, version, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
def parts(text):
    numbers = [int(part) for part in text.split(".")]
    return numbers + [0] * (4 - len(numbers))
lines = next((lines for key, lines in notes.items() if parts(key) == parts(version)), [])
if lines:
    open(out, "w").write("<ul>" + "".join(f"<li>{html.escape(line)}</li>" for line in lines) + "</ul>\n")
EOF

options=(--embed-release-notes --download-url-prefix "$repository/releases/download/$tag/"
         --full-release-notes-url "$repository/releases" --link "$repository")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$bin/generate_appcast" --ed-key-file - "${options[@]}" "$work"
else
  "$bin/generate_appcast" --account sushi-buddy "${options[@]}" "$work"
fi
cp "$work/appcast.xml" "$(dirname "$zip")/appcast.xml"
echo "Wrote $(dirname "$zip")/appcast.xml for $version"
