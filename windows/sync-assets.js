// Copies the art and lines both apps share from ../Resources into assets/,
// the folder the app reads at run time and the packager bundles. The seasonal sushis' images are
// the ones sushis.json names.
const fs = require('node:fs')
const path = require('node:path')

const from = path.join(__dirname, '..', 'Resources')
const to = path.join(__dirname, 'assets')
const looks = JSON.parse(fs.readFileSync(path.join(from, 'sushis.json'), 'utf8')).sushis
const files = [
  ...new Set([
    'body.png',
    'propeller.png',
    'MenuBarIcon.png',
    'lines.json',
    'whats-new.json',
    'sushis.json',
    'chime.wav',
    'whirr.wav',
    ...looks.flatMap(look => Object.values(look.images)),
  ]),
]

fs.mkdirSync(to, { recursive: true })
for (const file of files) {
  fs.copyFileSync(path.join(from, file), path.join(to, file))
}
