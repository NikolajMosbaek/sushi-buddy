const assert = require('node:assert/strict')
const { test } = require('node:test')

const { DEFAULTS } = require('../settings')
const usage = require('../usage')

// The same cases as mac/Tests/SushiBuddyTests/UsageTests.swift, so both apps send the same summary.

const ID = '00000000-0000-4000-8000-000000000000'
const env = {
  version: '1.8.0',
  build: '1.8.0',
  operatingSystem: 'Windows',
  systemVersion: '10.0.22631',
  systemMajorVersion: '11',
  architecture: 'x64',
  isDebug: false,
  installSource: 'download',
}

test('hashes the random ID the same way on both platforms', () => {
  assert.equal(usage.hash(ID), 'db8055e0e0307d5a016bec4dc338d69875eb0fb7e614a8b125b08fb082095d98')
})

test('a flight counts under what started it', () => {
  assert.equal(usage.trigger('motivate', false), 'menu')
  assert.equal(usage.trigger('motivate', true), 'auto')
  assert.equal(usage.trigger('motivate', false, 'shortcut'), 'shortcut')
  assert.equal(usage.trigger('motivate', false, 'script'), 'script')
  assert.equal(usage.trigger('break', true), 'break')
  assert.equal(usage.trigger('welcomeBack', true), 'welcomeBack')
  assert.equal(usage.trigger('pomodoroDone', false), 'pomodoro')
  assert.equal(usage.trigger('pomodoroBreakOver', false), 'pomodoro')
  assert.equal(usage.trigger('claudeDone', true), 'claudeDone')
  assert.equal(usage.trigger('claudeNeedsYou', true), 'claudeNeedsYou')
})

test('counts add up per key', () => {
  let record = usage.newRecord(ID)
  record = usage.count(record, 'flight.menu')
  record = usage.count(record, 'flight.menu')
  record = usage.count(record, 'pet')
  assert.deepEqual(record.counts, { 'flight.menu': 2, pet: 1 })
})

test('only settings that differ from the default count as changed, and never sharing itself', () => {
  assert.deepEqual(usage.changedKeys({ ...DEFAULTS, shareUsage: true }, DEFAULTS), [])
  assert.deepEqual(usage.changedKeys({ ...DEFAULTS, sound: 'chime', petting: false, shareUsage: true }, DEFAULTS), ['petting', 'sound'])
})

test('remembers every setting ever changed, also one changed back', () => {
  let record = usage.newRecord(ID)
  record = usage.noteSettings(record, { ...DEFAULTS, sound: 'chime' }, DEFAULTS)
  record = usage.noteSettings(record, { ...DEFAULTS, welcomeBack: true }, DEFAULTS)
  assert.deepEqual(record.everChanged, ['sound', 'welcomeBack'])
})

test('is due once per calendar day', () => {
  const today = usage.day(new Date(2026, 10, 12, 23, 59))
  assert.equal(today, '2026-11-12')
  assert.equal(usage.isDue(usage.newRecord(ID), today), true)
  assert.equal(usage.isDue({ ...usage.newRecord(ID), lastSent: '2026-11-12' }, today), false)
  assert.equal(usage.isDue({ ...usage.newRecord(ID), lastSent: '2026-11-11' }, today), true)
})

test('the summary has the app, every setting, and a count for every trigger and quiet rule', () => {
  let record = usage.newRecord(ID)
  record = usage.count(record, 'flight.shortcut')
  record = usage.count(record, 'skip.call')
  record = usage.count(record, 'pet')
  record = usage.noteSettings(record, { ...DEFAULTS, sound: 'chime' }, DEFAULTS)
  const summary = usage.payload({ ...DEFAULTS, sound: 'chime', shareUsage: true }, record, env, DEFAULTS)

  assert.equal(summary['TelemetryDeck.AppInfo.version'], '1.8.0')
  assert.equal(summary['TelemetryDeck.AppInfo.versionAndBuildNumber'], '1.8.0 1.8.0')
  assert.equal(summary['TelemetryDeck.Device.operatingSystem'], 'Windows')
  assert.equal(summary['TelemetryDeck.Device.platform'], 'Windows')
  assert.equal(summary['TelemetryDeck.Device.systemMajorVersion'], '11')
  assert.equal(summary['TelemetryDeck.Device.architecture'], 'x64')
  assert.equal(summary['TelemetryDeck.RunContext.isDebug'], false)
  assert.equal(summary['Sushi.Install.source'], 'download')
  assert.equal(summary['Sushi.Settings.sound'], 'chime')
  assert.equal(summary['Sushi.Settings.autoMotivateSeconds'], '0')
  assert.equal(summary['Sushi.Settings.petting'], 'true')
  assert.equal('Sushi.Settings.shareUsage' in summary, false)
  assert.equal(summary['Sushi.Settings.changedCount'], 1)
  assert.equal(summary['Sushi.Settings.everChanged'], 'sound')
  assert.equal(summary['Sushi.Flights.shortcut'], 1)
  assert.equal(summary['Sushi.Flights.menu'], 0)
  assert.equal(summary['Sushi.Skips.call'], 1)
  assert.equal(summary['Sushi.Skips.away'], 0)
  assert.equal(summary['Sushi.Pets'], 1)
  assert.equal(summary['Sushi.Health.unexpectedQuits'], 0)
  for (const trigger of usage.TRIGGERS) assert.equal(typeof summary[`Sushi.Flights.${trigger}`], 'number')
  for (const reason of usage.QUIET_REASONS) assert.equal(typeof summary[`Sushi.Skips.${reason}`], 'number')
  for (const value of Object.values(summary)) assert.ok(['string', 'number', 'boolean'].includes(typeof value))
})

test('nothing changed reads as none', () => {
  const summary = usage.payload({ ...DEFAULTS, shareUsage: true }, usage.newRecord(ID), env, DEFAULTS)
  assert.equal(summary['Sushi.Settings.everChanged'], 'none')
  assert.equal(summary['Sushi.Settings.changedCount'], 0)
})

test('the request is one signal with the hashed ID, never the ID itself', () => {
  const record = usage.newRecord(ID)
  const body = usage.body('APP-ID', record, { 'Sushi.Pets': 0 }, true)
  assert.deepEqual(body, [
    { appID: 'APP-ID', clientUser: usage.hash(ID), type: 'Sushi.dailySummary', isTestMode: true, payload: { 'Sushi.Pets': 0 } },
  ])
  assert.equal(JSON.stringify(body).includes(ID), false)
})

test('after a send, only what was sent comes off the counts', () => {
  let sent = usage.newRecord(ID)
  sent = usage.count(sent, 'flight.menu')
  sent = usage.count(sent, 'pet')
  // A flight while the request was out.
  const now = usage.count(usage.count(sent, 'flight.menu'), 'flight.auto')
  const after = usage.afterSend(now, sent, '2026-11-12')
  assert.deepEqual(after.counts, { 'flight.menu': 1, 'flight.auto': 1 })
  assert.equal(after.lastSent, '2026-11-12')
  assert.equal(after.id, ID)
})

test('a run that ended while the computer stayed on counts as an unexpected quit', () => {
  // Started 600 s ago; the computer has been up for an hour: the app died, the computer didn't.
  assert.equal(usage.quitUnexpectedly(1000, 1600, 3600), true)
  // Up for only 100 s: the computer restarted since, which ends every app.
  assert.equal(usage.quitUnexpectedly(1000, 1600, 100), false)
  assert.equal(usage.quitUnexpectedly(null, 1600, 3600), false)
})

test("reads Windows' major version from its build number", () => {
  assert.equal(usage.windowsMajor('10.0.22631'), '11')
  assert.equal(usage.windowsMajor('10.0.19045'), '10')
  assert.equal(usage.windowsMajor('nonsense'), '10')
})

test('tells a winget install from a download by where the exe is', () => {
  assert.equal(usage.installSource(String.raw`C:\Users\a\AppData\Local\Microsoft\WinGet\Packages\NSSCode.SushiBuddy_x\Sushi Buddy.exe`), 'winget')
  assert.equal(usage.installSource(String.raw`C:\Users\a\Downloads\Sushi-Buddy-windows-x64\Sushi Buddy.exe`), 'download')
})
