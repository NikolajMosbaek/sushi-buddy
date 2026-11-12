// Every choice in Settings, with the same names and defaults as
// mac/Sources/SushiBuddy/Preferences.swift. Kept in %APPDATA%\Sushi Buddy\settings.json.
//
// Defaults: whatever flies or makes a sound on its own starts off; whatever only holds
// automatic flights back starts on; looks (paths, petting, lines) start on.
const fs = require('node:fs')
const path = require('node:path')

const CHOICES = {
  autoMotivateSeconds: [0, 900, 1800, 3600, 7200, 14400],
  breakReminderMinutes: [0, 30, 45, 60, 90],
  awayMinutes: [5, 10, 15, 30],
  flightPath: ['random', 'classic', 'loop', 'bounce', 'zigzag'],
  sushi: ['calendar', 'classic', 'fall', 'jday', 'santa', 'bunny', 'metalhead'],
  sound: ['off', 'chime', 'whirr'],
  hotkey: ['off', 'Control+Alt+Shift+S', 'Control+Alt+S', 'Control+Alt+Shift+M'],
  claudeMinMinutes: [0, 1, 2, 5, 10],
  pomodoroFocusMinutes: [15, 25, 45, 50],
  pomodoroBreakMinutes: [5, 10],
}

const DEFAULTS = {
  autoMotivateSeconds: 0,
  breakReminderMinutes: 0,
  welcomeBack: false,
  awayMinutes: 10,
  quietDuringFocus: true,
  quietOnCalls: true,
  quietWhenPresenting: true,
  quietWhenAway: true,
  flightPath: 'random',
  sushi: 'calendar',
  petting: true,
  sound: 'off',
  hotkey: 'Control+Alt+Shift+S',
  contextLines: true,
  streaks: true,
  listen: true,
  claudeDone: true,
  claudeMinMinutes: 2,
  claudeNeedsYou: true,
  pomodoroFocusMinutes: 25,
  pomodoroBreakMinutes: 5,
  pomodoroLongBreaks: true,
  checkForUpdates: true,
  // Only ever on because you turned it on.
  shareUsage: false,
}

/** Every setting, each one the stored value where that is one of its choices, else its default. */
function normalize(raw) {
  const stored = raw && typeof raw === 'object' ? raw : {}
  const settings = {}
  for (const [key, fallback] of Object.entries(DEFAULTS)) {
    const value = stored[key]
    const valid = CHOICES[key] ? CHOICES[key].includes(value) : typeof value === typeof fallback
    settings[key] = valid ? value : fallback
  }
  return settings
}

/** The file as stored: settings plus the app's own bookkeeping (the streak). */
function readFile(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'))
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
  } catch {
    return {}
  }
}

function writeFile(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(contents, null, 2))
}

/** Stores one change, refusing a value outside the setting's choices. */
function update(file, key, value) {
  if (!(key in DEFAULTS)) throw new Error(`no setting called ${key}`)
  const next = normalize({ ...normalize(readFile(file)), [key]: value })
  if (next[key] !== value) throw new Error(`${JSON.stringify(value)} is not a choice for ${key}`)
  writeFile(file, { ...readFile(file), [key]: value })
  return next
}

module.exports = { CHOICES, DEFAULTS, normalize, readFile, writeFile, update }
