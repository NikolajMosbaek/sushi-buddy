// The anonymous usage summary: once a day, only while Share anonymous usage statistics is on, the
// app tells TelemetryDeck which settings you picked and how often the sushi flew, under a random ID
// made when you turned it on (and forgotten when you turn it off), hashed before it leaves. Never a
// line, a project or anything you typed. The same rules and fields as mac/Sources/SushiBuddy/Usage.swift.
const crypto = require('node:crypto')

const ENDPOINT = 'https://nom.telemetrydeck.com/v2/namespace/com.nsscode/'
const SIGNAL = 'Sushi.dailySummary'
const TRIGGERS = ['menu', 'shortcut', 'script', 'auto', 'break', 'welcomeBack', 'pomodoro', 'claudeDone', 'claudeNeedsYou']
const QUIET_REASONS = ['away', 'focus', 'call', 'presenting']

const newRecord = id => ({ id, counts: {}, everChanged: [], lastSent: null })

const hash = id => crypto.createHash('sha256').update(id).digest('hex')

/** What started a flight: `via` when the caller knows (the shortcut, a script), else the occasion. */
function trigger(occasion, automatic, via) {
  if (via) return via
  if (occasion === 'motivate') return automatic ? 'auto' : 'menu'
  if (occasion.startsWith('pomodoro')) return 'pomodoro'
  return occasion
}

const count = (record, key) => ({ ...record, counts: { ...record.counts, [key]: (record.counts[key] ?? 0) + 1 } })

/** The settings that differ from their defaults; sharing itself is always on when anything is sent. */
function changedKeys(settings, defaults) {
  return Object.keys(defaults)
    .filter(key => key !== 'shareUsage' && settings[key] !== defaults[key])
    .sort()
}

function noteSettings(record, settings, defaults) {
  const everChanged = [...new Set([...record.everChanged, ...changedKeys(settings, defaults)])].sort()
  return { ...record, everChanged }
}

/** `date` as YYYY-MM-DD in local time: one summary per calendar day where you are. */
function day(date) {
  const pad = number => String(number).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

const isDue = (record, today) => record.lastSent !== today

/**
 * The summary: the app and system under TelemetryDeck's own names (its charts read those), every
 * setting as text, and a count for every trigger and quiet rule, zero included. Flat, as the API wants.
 */
function payload(settings, record, env, defaults) {
  const counted = key => record.counts[key] ?? 0
  const summary = {
    'TelemetryDeck.AppInfo.version': env.version,
    'TelemetryDeck.AppInfo.buildNumber': env.build,
    'TelemetryDeck.AppInfo.versionAndBuildNumber': `${env.version} ${env.build}`,
    'TelemetryDeck.Device.operatingSystem': env.operatingSystem,
    'TelemetryDeck.Device.platform': env.operatingSystem,
    'TelemetryDeck.Device.systemVersion': env.systemVersion,
    'TelemetryDeck.Device.systemMajorVersion': env.systemMajorVersion,
    'TelemetryDeck.Device.architecture': env.architecture,
    'TelemetryDeck.RunContext.isDebug': env.isDebug,
    'Sushi.Install.source': env.installSource,
    'Sushi.Settings.changedCount': changedKeys(settings, defaults).length,
    'Sushi.Settings.everChanged': record.everChanged.length ? record.everChanged.join(',') : 'none',
    'Sushi.Pets': counted('pet'),
    'Sushi.Health.unexpectedQuits': counted('unexpectedQuit'),
  }
  for (const key of Object.keys(defaults)) {
    if (key !== 'shareUsage') summary[`Sushi.Settings.${key}`] = String(settings[key])
  }
  for (const name of TRIGGERS) summary[`Sushi.Flights.${name}`] = counted(`flight.${name}`)
  for (const reason of QUIET_REASONS) summary[`Sushi.Skips.${reason}`] = counted(`skip.${reason}`)
  return Object.fromEntries(Object.entries(summary).sort(([a], [b]) => (a < b ? -1 : 1)))
}

/** What goes to TelemetryDeck: one signal, with the ID hashed. */
function body(appID, record, summary, testMode) {
  return [{ appID, clientUser: hash(record.id), type: SIGNAL, isTestMode: testMode, payload: summary }]
}

/** After a send: what was sent comes off the counts, so a flight during the request isn't lost. */
function afterSend(record, sent, today) {
  const counts = {}
  for (const [key, value] of Object.entries(record.counts)) {
    const left = value - (sent.counts[key] ?? 0)
    if (left > 0) counts[key] = left
  }
  return { ...record, counts, lastSent: today }
}

/**
 * Whether the last run ended without quitting, while the computer stayed on: it started at
 * `runningSince` and the computer has been up since before then. A restart ends every app, so it
 * doesn't count. All in seconds.
 */
function quitUnexpectedly(runningSince, now, uptime) {
  return runningSince != null && uptime >= now - runningSince
}

/** Windows 11 still says 10.0; its builds start at 22000. */
function windowsMajor(release) {
  const build = Number(String(release).split('.')[2])
  return build >= 22000 ? '11' : '10'
}

const installSource = execPath => (/\\winget\\/i.test(execPath) ? 'winget' : 'download')

module.exports = {
  ENDPOINT,
  SIGNAL,
  TRIGGERS,
  QUIET_REASONS,
  newRecord,
  hash,
  trigger,
  count,
  changedKeys,
  noteSettings,
  day,
  isDue,
  payload,
  body,
  afterSend,
  quitUnexpectedly,
  windowsMajor,
  installSource,
}
