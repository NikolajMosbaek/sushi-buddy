const assert = require('node:assert/strict')
const { test } = require('node:test')

const { compareVersions, outcome, parseVersion, pickDownload } = require('../update')

const release = {
  tag_name: 'v1.2.0',
  html_url: 'https://github.com/NikolajMosbaek/sushi-buddy/releases/tag/v1.2.0',
  assets: [
    { name: 'Sushi-Buddy-windows-x64.zip', browser_download_url: 'https://example.com/x64.zip' },
    { name: 'Sushi-Buddy-windows-arm64.zip', browser_download_url: 'https://example.com/arm64.zip' },
    { name: 'Sushi-Buddy-macOS-arm64.zip', browser_download_url: 'https://example.com/mac.zip' },
  ],
}

test('reads a tag with or without the v, and refuses what is not a version', () => {
  assert.deepEqual(parseVersion('v1.2.0'), [1, 2, 0])
  assert.deepEqual(parseVersion('1.1'), [1, 1])
  assert.equal(parseVersion('latest'), null)
  assert.equal(parseVersion('1.x'), null)
  assert.equal(parseVersion(''), null)
})

test('compares part by part as numbers, missing parts as zero', () => {
  assert.equal(compareVersions('1.10', '1.9'), 1)
  assert.equal(compareVersions('1.1', '1.1.0'), 0)
  assert.equal(compareVersions('v2.0', '1.99.9'), 1)
  assert.equal(compareVersions('1.0.0', '1.1.0'), -1)
})

test('picks the download for this machine, else the release page', () => {
  assert.equal(pickDownload(release, 'x64'), 'https://example.com/x64.zip')
  assert.equal(pickDownload(release, 'arm64'), 'https://example.com/arm64.zip')
  assert.equal(pickDownload(release, 'ia32'), release.html_url)
})

test('a newer release is an update; the same or an older one is not', () => {
  assert.equal(outcome(release, '1.1.0', 'x64').status, 'available')
  assert.equal(outcome(release, '1.1.0', 'x64').url, 'https://example.com/x64.zip')
  assert.equal(outcome(release, '1.2.0', 'x64').status, 'up-to-date')
  assert.equal(outcome(release, '1.3.0', 'x64').status, 'up-to-date')
})
