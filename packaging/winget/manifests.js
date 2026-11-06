// Writes the winget manifests for one release: node manifests.js <version> <folder with the
// Windows zips> <output folder>. The release workflow runs it and attaches the result; to
// publish to winget, submit that folder to microsoft/winget-pkgs (for example with
// `wingetcreate submit <folder>`).
const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')

const [version, zips, out] = process.argv.slice(2)
if (!version || !zips || !out) {
  console.error('usage: node manifests.js <version> <zip folder> <output folder>')
  process.exit(2)
}

const id = 'NikolajMosbaek.SushiBuddy'
const repository = 'https://github.com/NikolajMosbaek/sushi-buddy'
const schema = '1.6.0'
const header = kind =>
  `# yaml-language-server: $schema=https://aka.ms/winget-manifest.${kind}.${schema}.schema.json\n`

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase()
}

const installers = ['x64', 'arm64'].map(arch => {
  const name = `Sushi-Buddy-windows-${arch}.zip`
  return [
    `  - Architecture: ${arch}`,
    `    InstallerUrl: ${repository}/releases/download/v${version}/${name}`,
    `    InstallerSha256: ${sha256(path.join(zips, name))}`,
    `    NestedInstallerFiles:`,
    `      - RelativeFilePath: Sushi Buddy-win32-${arch}\\Sushi Buddy.exe`,
    `        PortableCommandAlias: sushi-buddy`,
  ].join('\n')
})

const files = {
  [`${id}.yaml`]: `${header('version')}PackageIdentifier: ${id}
PackageVersion: ${version}
DefaultLocale: en-US
ManifestType: version
ManifestVersion: ${schema}
`,
  [`${id}.installer.yaml`]: `${header('installer')}PackageIdentifier: ${id}
PackageVersion: ${version}
InstallerType: zip
NestedInstallerType: portable
Installers:
${installers.join('\n')}
ManifestType: installer
ManifestVersion: ${schema}
`,
  [`${id}.locale.en-US.yaml`]: `${header('defaultLocale')}PackageIdentifier: ${id}
PackageVersion: ${version}
PackageLocale: en-US
Publisher: Nikolaj Søgaard Simonsen
PackageName: Sushi Buddy
PackageUrl: ${repository}
License: Proprietary
ShortDescription: A sushi in a propeller hat that flies across your screen to cheer you on.
Tags:
  - motivation
  - pomodoro
  - tray
ReleaseNotesUrl: ${repository}/releases/tag/v${version}
ManifestType: defaultLocale
ManifestVersion: ${schema}
`,
}

const folder = path.join(out, 'manifests', 'n', 'NikolajMosbaek', 'SushiBuddy', version)
fs.mkdirSync(folder, { recursive: true })
for (const [name, text] of Object.entries(files)) {
  fs.writeFileSync(path.join(folder, name), text)
  console.log(path.join(folder, name))
}
