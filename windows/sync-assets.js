// Copies the art and lines both apps share from ../Resources into assets/,
// the folder the app reads at run time and the packager bundles.
const fs = require('node:fs')
const path = require('node:path')

const from = path.join(__dirname, '..', 'Resources')
const to = path.join(__dirname, 'assets')
const files = ['body.png', 'propeller.png', 'MenuBarIcon.png', 'lines.json', 'chime.wav', 'whirr.wav']

fs.mkdirSync(to, { recursive: true })
for (const file of files) {
  fs.copyFileSync(path.join(from, file), path.join(to, file))
}
