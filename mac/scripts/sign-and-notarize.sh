#!/bin/bash
# Signs Sushi Buddy.app with a Developer ID, notarizes it and staples the ticket, so
# Gatekeeper opens it without a warning. The release workflow runs it when these secrets
# are set (Settings → Secrets and variables → Actions in the GitHub repository):
#
#   APPLE_CERTIFICATE           the "Developer ID Application" certificate and key, exported
#                               from Keychain Access as a .p12, base64-encoded (base64 -i cert.p12)
#   APPLE_CERTIFICATE_PASSWORD  the password the .p12 was exported with
#   APPLE_SIGNING_IDENTITY      e.g. "Developer ID Application: Your Name (TEAMID1234)"
#   APPLE_ID                    the Apple Account of the developer team
#   APPLE_TEAM_ID               the team's ID (TEAMID1234)
#   APPLE_APP_PASSWORD          an app-specific password for that account (account.apple.com)
#
# Usage: sign-and-notarize.sh "path/to/Sushi Buddy.app"
set -euo pipefail
app="$1"
work="${RUNNER_TEMP:-$(mktemp -d)}"
keychain="$work/signing.keychain-db"

security create-keychain -p "" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "" "$keychain"
echo "$APPLE_CERTIFICATE" | base64 --decode > "$work/certificate.p12"
security import "$work/certificate.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$keychain" > /dev/null
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$app"
codesign --verify --strict --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$work/notarize.zip"
xcrun notarytool submit "$work/notarize.zip" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
