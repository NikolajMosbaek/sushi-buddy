const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { test } = require('node:test')

const { RELEASE_NOTES, display, pick, steps } = require('../whats-new')

// The same cases as mac/Tests/SushiBuddyTests/WhatsNewTests.swift, so both apps pick the same notes.

const notes = {
  '1.6': ['Tips!', 'Versions!'],
  '1.5': ['The tour.'],
  '1.4': [],
  later: ['Not a version.'],
}

test("picks the installed version's own notes", () => {
  assert.deepEqual(pick(notes, '1.6'), { version: '1.6', lines: ['Tips!', 'Versions!'] })
})

test('a version without notes gets the newest older ones', () => {
  assert.equal(pick(notes, '1.6.1').version, '1.6')
  assert.equal(pick(notes, '1.5.9').version, '1.5')
})

test('a patch zero counts as its minor', () => {
  assert.equal(pick(notes, '1.6.0').version, '1.6')
})

test('skips empty lists and keys that are not versions', () => {
  assert.equal(pick(notes, '1.4.2'), null)
  assert.equal(pick(notes, '1.3'), null)
})

test('shows a version without trailing zero parts', () => {
  assert.equal(display('1.5.0'), '1.5')
  assert.equal(display('1.5'), '1.5')
  assert.equal(display('1.4.1'), '1.4.1')
  assert.equal(display('2.0.0'), '2.0')
})

test('one step per line, the first naming the version, the last linking the release notes', () => {
  const shown = steps(notes, '1.6.0')
  assert.deepEqual(shown.map(step => step.text), ['New in 1.6: Tips!', 'Versions!'])
  assert.deepEqual(shown.map(step => step.link), [null, RELEASE_NOTES])
  assert.equal(new Set(shown.map(step => step.id)).size, shown.length)
})

test('without notes the sushi points to the release notes', () => {
  for (const installed of ['1.0', '?']) {
    const shown = steps(notes, installed)
    assert.equal(shown.length, 1)
    assert.equal(shown[0].link, RELEASE_NOTES)
  }
})

test("the bundled notes are versions with lines and cover the app's version", () => {
  const bundled = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'Resources', 'whats-new.json'), 'utf8'))
  for (const [key, lines] of Object.entries(bundled)) {
    assert.ok(/^\d+(\.\d+)*$/.test(key), `${key} is not a version`)
    assert.ok(Array.isArray(lines) && lines.length > 0, `${key} has no lines`)
  }
  const { version } = require('../package.json')
  assert.notEqual(pick(bundled, version), null, `whats-new.json has nothing for ${version}`)
})
