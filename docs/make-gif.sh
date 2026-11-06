#!/bin/bash
# Renders docs/sushi-buddy.gif, the README's animation, from the app's own
# drawing: one flight, frame by frame, through the Windows build's --preview.
# Needs `npm install` in windows/ and Python 3 with Pillow.
set -euo pipefail
cd "$(dirname "$0")/.."

fps=20
frames=$(mktemp -d)
trap 'rm -rf "$frames"' EXIT

moments=$(python3 -c "print(','.join(f'{i / $fps:.2f}' for i in range(int(7.4 * $fps))))")
(cd windows && npm run -s assets && npx electron . --preview "$frames/frame.png" --at "$moments" > /dev/null)
python3 docs/make-gif.py "$frames" docs/sushi-buddy.gif "$fps"
ls -l docs/sushi-buddy.gif
