#!/bin/sh
# Puts the website together in a new or empty folder: the pages in site/, plus the apps' own sushi
# (windows/looks.js, flight.js, sushi-view.js, sushi.css) and art (Resources/), so the sushi on the
# page flies exactly like the one on a desktop. The version shown is the latest release's: VERSION,
# or GitHub's answer when it's unset. Every asset address carries the commit, so a browser never
# pairs a new page with an old stylesheet it cached.
#
#   site/build.sh _site && python3 -m http.server --directory _site 8080
set -eu

out=${1:?usage: site/build.sh <folder>}
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -e "$out" ] && [ -n "$(ls -A "$out")" ]; then
  echo "site/build.sh: $out is not empty" >&2
  exit 1
fi

version=${VERSION:-$(gh release view --repo NikolajMosbaek/sushi-buddy --json tagName -q .tagName)}
version=${version#v}
rev=$(git -C "$root" rev-parse --short HEAD)

mkdir -p "$out/assets"
cp "$root"/site/site.css "$root"/site/site.js "$root"/site/icon.png "$root"/site/og.png "$out/"
cp "$root"/windows/looks.js "$root"/windows/flight.js "$root"/windows/sushi-view.js "$root"/windows/sushi.css "$out/"
cp "$root"/Resources/sushis.json "$root"/Resources/lines.json "$root"/Resources/body.png "$root"/Resources/propeller.png \
  "$root"/Resources/sushi-*.png "$out/assets/"
sed -e "s/{{VERSION}}/$version/g" -e "s/{{REV}}/$rev/g" "$root/site/index.html" > "$out/index.html"
echo "site/build.sh: Sushi Buddy $version at $rev in $out"
