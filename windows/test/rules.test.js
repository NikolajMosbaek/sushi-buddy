const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { test } = require('node:test')

const { DEFAULTS, normalize, update } = require('../settings')
const { advanceStreak, mergeLines, occasions, pickLine } = require('../lines')
const { breakTick, isAway, presenceTick, quietReason } = require('../presence')
const { describe, nextPhase, startPomodoro } = require('../pomodoro')
const { ClaudeTracker, projectName } = require('../claude')
const { flyMessage, listen, vet } = require('../listener')
const { parseSystem, signalsFrom } = require('../system')
const { DURATION, FLY_IN, FLY_OUT, HOVER, PATHS, pathOffset, pose, previewFlight } = require('../flight')

const MINUTE = 60 * 1000
const bundled = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'Resources', 'lines.json'), 'utf8'))
// A Tuesday at noon, a Monday morning and a Friday night, local time.
const tuesdayNoon = new Date(2026, 10, 3, 12, 0)
const mondayMorning = new Date(2026, 10, 2, 8, 0)
const fridayNight = new Date(2026, 10, 6, 23, 0)

test('settings fall back to the default for anything missing or outside the choices', () => {
  assert.deepEqual(normalize(undefined), DEFAULTS)
  const settings = normalize({ autoMotivateSeconds: 1800, sound: 'banjo', petting: 'yes', welcomeBack: true })
  assert.equal(settings.autoMotivateSeconds, 1800)
  assert.equal(settings.sound, 'off')
  assert.equal(settings.petting, true)
  assert.equal(settings.welcomeBack, true)
})

test('nothing flies or sounds on its own by default; the quiet rules start on', () => {
  assert.equal(DEFAULTS.autoMotivateSeconds, 0)
  assert.equal(DEFAULTS.breakReminderMinutes, 0)
  assert.equal(DEFAULTS.welcomeBack, false)
  assert.equal(DEFAULTS.sound, 'off')
  for (const key of ['quietDuringFocus', 'quietOnCalls', 'quietWhenPresenting', 'quietWhenAway']) assert.equal(DEFAULTS[key], true)
})

test('an update keeps the other settings and the streak, and refuses a value that is not a choice', () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'sushi-')), 'settings.json')
  fs.writeFileSync(file, JSON.stringify({ autoMotivateSeconds: 3600, streak: { days: 3, lastDay: '2026-11-02' } }))
  assert.equal(update(file, 'sound', 'chime').autoMotivateSeconds, 3600)
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')).streak, { days: 3, lastDay: '2026-11-02' })
  assert.throws(() => update(file, 'awayMinutes', 7))
  assert.throws(() => update(file, 'nonsense', true))
})

test("your own lines replace the built-in ones per occasion; the rest stay", () => {
  const { lines, error } = mergeLines(bundled, JSON.stringify({ anytime: ['Mine!'], friday: [], bogus: ['x'] }))
  assert.equal(error, null)
  assert.deepEqual(lines.anytime, ['Mine!'])
  assert.deepEqual(lines.friday, bundled.friday)
  assert.equal(lines.bogus, undefined)
})

test('a 1.3-style plain list is anytime lines; broken JSON keeps the built-in lines and says why', () => {
  assert.deepEqual(mergeLines(bundled, '["Old style"]').lines.anytime, ['Old style'])
  const broken = mergeLines(bundled, '{ "anytime": [')
  assert.equal(broken.lines, bundled)
  assert.match(broken.error, /isn't valid JSON/)
  assert.equal(mergeLines(bundled, null).error, null)
})

test('occasions follow the clock and the weekday', () => {
  assert.deepEqual(occasions(tuesdayNoon), [])
  assert.deepEqual(occasions(mondayMorning), ['morning', 'monday'])
  assert.deepEqual(occasions(fridayNight), ['lateNight', 'friday'])
})

test('a motivation picks an occasion line on heads, an anytime line on tails, and anytime only with occasions off', () => {
  const lines = { anytime: ['any'], morning: ['morning'], monday: ['monday'] }
  const heads = [0.0, 0.1, 0.0]
  const sequence = values => () => values.shift()
  assert.equal(pickLine('motivate', lines, { date: mondayMorning, contextLines: true }, sequence([0.1, 0.0])), 'morning')
  assert.equal(pickLine('motivate', lines, { date: mondayMorning, contextLines: true }, sequence([0.9, 0.0])), 'any')
  assert.equal(pickLine('motivate', lines, { date: mondayMorning, contextLines: false }, sequence(heads)), 'any')
})

test('the first motivation of a day from day 2 on is the streak line, with the count filled in', () => {
  const lines = { anytime: ['any'], streak: ['Day {days}!'] }
  const date = tuesdayNoon
  assert.equal(pickLine('motivate', lines, { date, streak: { days: 4, firstToday: true } }, () => 0), 'Day 4!')
  assert.equal(pickLine('motivate', lines, { date, streak: { days: 4, firstToday: false } }, () => 0), 'any')
  assert.equal(pickLine('motivate', lines, { date, streak: { days: 1, firstToday: true } }, () => 0), 'any')
})

test('other occasions use their own lines, fall back to anytime, and fill in the project', () => {
  const lines = { anytime: ['any'], claudeDone: ['Done in {project}'] }
  assert.equal(pickLine('claudeDone', lines, { date: tuesdayNoon, project: 'sushi' }, () => 0), 'Done in sushi')
  assert.equal(pickLine('claudeDone', lines, { date: tuesdayNoon }, () => 0), 'Done in your project')
  assert.equal(pickLine('break', lines, { date: tuesdayNoon }, () => 0), 'any')
})

test('a streak grows on consecutive days, holds within a day, and starts over after a gap', () => {
  const first = advanceStreak(undefined, tuesdayNoon)
  assert.deepEqual(first, { streak: { days: 1, lastDay: '2026-11-03' }, firstToday: true })
  assert.equal(advanceStreak(first.streak, new Date(2026, 10, 3, 18)).firstToday, false)
  assert.deepEqual(advanceStreak(first.streak, new Date(2026, 10, 4, 9)).streak, { days: 2, lastDay: '2026-11-04' })
  assert.deepEqual(advanceStreak(first.streak, new Date(2026, 10, 6, 9)).streak, { days: 1, lastDay: '2026-11-06' })
  // Across a month end.
  assert.equal(advanceStreak({ days: 5, lastDay: '2026-10-31' }, new Date(2026, 10, 1, 9)).streak.days, 6)
})

test('the quiet rules give the first reason that holds and is switched on', () => {
  const all = { away: true, focus: true, call: true, presenting: true }
  assert.equal(quietReason(DEFAULTS, all), 'away')
  assert.equal(quietReason({ ...DEFAULTS, quietWhenAway: false }, all), 'focus')
  assert.equal(quietReason({ ...DEFAULTS, quietWhenAway: false, quietDuringFocus: false }, all), 'call')
  assert.equal(quietReason({ ...DEFAULTS, quietWhenPresenting: false }, { presenting: true }), null)
  assert.equal(quietReason(DEFAULTS, { presenting: true }), 'presenting')
  assert.equal(quietReason(DEFAULTS, {}), null)
  const allOff = { quietWhenAway: false, quietDuringFocus: false, quietOnCalls: false, quietWhenPresenting: false }
  assert.equal(quietReason(allOff, all), null)
})

test('away means locked, or idle for the chosen minutes', () => {
  assert.equal(isAway({ idleSeconds: 599, locked: false }, 10), false)
  assert.equal(isAway({ idleSeconds: 600, locked: false }, 10), true)
  assert.equal(isAway({ idleSeconds: 0, locked: true }, 10), true)
})

test('coming back is noticed once, with how long you were away', () => {
  let state = { awaySince: null }
  let tick = presenceTick(state, { now: 1_000_000, away: true, idleSeconds: 600 })
  assert.equal(tick.cameBack, false)
  assert.equal(tick.state.awaySince, 1_000_000 - 600_000)
  tick = presenceTick(tick.state, { now: 2_000_000, away: true, idleSeconds: 1600 })
  assert.equal(tick.state.awaySince, 400_000)
  tick = presenceTick(tick.state, { now: 2_100_000, away: false, idleSeconds: 2 })
  assert.equal(tick.cameBack, true)
  assert.equal(tick.awayFor, 1_700_000)
  state = tick.state
  assert.equal(presenceTick(state, { now: 2_200_000, away: false, idleSeconds: 1 }).cameBack, false)
})

test('a break reminder comes after the interval at the computer; five idle minutes count as a break', () => {
  let state = { activeSince: 0 }
  assert.equal(breakTick(state, { now: 44 * MINUTE, idleSeconds: 0, intervalMinutes: 45 }).remind, false)
  const due = breakTick(state, { now: 45 * MINUTE, idleSeconds: 0, intervalMinutes: 45 })
  assert.equal(due.remind, true)
  assert.equal(due.state.activeSince, 45 * MINUTE)
  state = breakTick(state, { now: 40 * MINUTE, idleSeconds: 300, intervalMinutes: 45 }).state
  assert.equal(breakTick(state, { now: 80 * MINUTE, idleSeconds: 0, intervalMinutes: 45 }).remind, false)
  assert.equal(breakTick({ activeSince: 0 }, { now: 999 * MINUTE, idleSeconds: 0, intervalMinutes: 0 }).remind, false)
})

test('a pomodoro alternates focus and breaks, with every fourth break long', () => {
  const settings = { pomodoroFocusMinutes: 25, pomodoroBreakMinutes: 5, pomodoroLongBreaks: true }
  let state = startPomodoro(0, settings)
  assert.deepEqual(state, { phase: 'focus', endsAt: 25 * MINUTE, completed: 0 })
  const phases = []
  let now = 0
  for (let i = 0; i < 8; i += 1) {
    now = state.endsAt
    const next = nextPhase(state, now, settings)
    phases.push(`${next.state.phase}:${next.line}`)
    state = next.state
  }
  assert.deepEqual(phases, [
    'break:pomodoroDone',
    'focus:pomodoroBreakOver',
    'break:pomodoroDone',
    'focus:pomodoroBreakOver',
    'break:pomodoroDone',
    'focus:pomodoroBreakOver',
    'longBreak:pomodoroDone',
    'focus:pomodoroBreakOver',
  ])
  const short = nextPhase({ phase: 'focus', endsAt: 0, completed: 3 }, 0, { ...settings, pomodoroLongBreaks: false })
  assert.equal(short.state.phase, 'break')
  assert.equal(describe({ phase: 'focus', endsAt: 12 * MINUTE + 1, completed: 0 }, 0), 'Focus, 13 min left')
  assert.equal(describe({ phase: 'longBreak', endsAt: 10, completed: 4 }, 0), 'Long break, 1 min left')
})

test('Claude is cheered only after a turn as long as the minimum, per session', () => {
  const settings = { claudeDone: true, claudeMinMinutes: 2, claudeNeedsYou: true }
  const claude = new ClaudeTracker()
  const event = (name, session, extra = {}) => ({ hook_event_name: name, session_id: session, cwd: '/work/sushi-buddy', ...extra })
  assert.equal(claude.handle(event('UserPromptSubmit', 'a'), 0, settings), null)
  assert.equal(claude.handle(event('UserPromptSubmit', 'b'), MINUTE, settings), null)
  assert.equal(claude.handle(event('Stop', 'b'), 2 * MINUTE, settings), null)
  assert.deepEqual(claude.handle(event('Stop', 'a'), 2 * MINUTE, settings), { kind: 'claudeDone', project: 'sushi-buddy' })
  // A Stop with no prompt seen (the app started mid-turn) only cheers with no minimum.
  assert.equal(claude.handle(event('Stop', 'c'), 3 * MINUTE, settings), null)
  assert.deepEqual(claude.handle(event('Stop', 'c'), 3 * MINUTE, { ...settings, claudeMinMinutes: 0 }).kind, 'claudeDone')
  claude.handle(event('UserPromptSubmit', 'd'), 0, settings)
  assert.equal(claude.handle(event('Stop', 'd'), 9 * MINUTE, { ...settings, claudeDone: false }), null)
  assert.equal(claude.lastHeard, 9 * MINUTE)
})

test('Claude needing permission flies; other notifications do not', () => {
  const settings = { claudeDone: true, claudeMinMinutes: 2, claudeNeedsYou: true }
  const claude = new ClaudeTracker()
  const notification = extra => ({ hook_event_name: 'Notification', session_id: 'a', cwd: 'C:\\work\\app', ...extra })
  assert.deepEqual(claude.handle(notification({ notification_type: 'permission_prompt' }), 0, settings), {
    kind: 'claudeNeedsYou',
    project: 'app',
  })
  assert.equal(claude.handle(notification({ notification_type: 'idle_prompt', message: 'permission' }), 0, settings), null)
  assert.equal(claude.handle(notification({ message: 'Claude needs your permission to use Bash' }), 0, settings).kind, 'claudeNeedsYou')
  assert.equal(claude.handle(notification({ notification_type: 'permission_prompt' }), 0, { ...settings, claudeNeedsYou: false }), null)
  assert.equal(projectName(undefined), '')
})

test('the listener takes only this computer’s own requests to its routes', () => {
  const headers = { host: '127.0.0.1:7874' }
  assert.deepEqual(vet({ method: 'POST', url: '/claude', headers }, 7874), { status: 204, route: 'claude' })
  assert.deepEqual(vet({ method: 'POST', url: '/fly?x=1', headers: { host: 'localhost:7874' } }, 7874), { status: 204, route: 'fly' })
  assert.deepEqual(vet({ method: 'GET', url: '/', headers }, 7874), { status: 200, route: 'hello' })
  assert.equal(vet({ method: 'POST', url: '/claude', headers: { ...headers, origin: 'https://evil.example' } }, 7874).status, 403)
  assert.equal(vet({ method: 'POST', url: '/claude', headers: { host: 'evil.example:7874' } }, 7874).status, 403)
  assert.equal(vet({ method: 'POST', url: '/claude', headers: {} }, 7874).status, 403)
  assert.equal(vet({ method: 'GET', url: '/claude', headers }, 7874).status, 404)
  assert.equal(vet({ method: 'POST', url: '/delete', headers }, 7874).status, 404)
})

test('a /fly message comes as JSON or plain text, cleaned and cut to 140 characters', () => {
  assert.equal(flyMessage('{"message": "Hi there"}'), 'Hi there')
  assert.equal(flyMessage('Plain hello'), 'Plain hello')
  assert.equal(flyMessage(''), null)
  assert.equal(flyMessage('{}'), null)
  assert.equal(flyMessage('{"message": "a\\nb\\u0007c"}'), 'a b c')
  assert.equal(Array.from(flyMessage('🍣'.repeat(200))).length, 140)
})

test('the listener answers on 127.0.0.1 and hands over what it was sent', async () => {
  const port = 40000 + Math.floor(Math.random() * 20000)
  const received = []
  const { server, error } = await listen(port, {
    version: '9.9',
    onClaude: event => received.push(['claude', event.hook_event_name]),
    onFly: message => received.push(['fly', message]),
  })
  assert.equal(error, undefined)
  try {
    const base = `http://127.0.0.1:${port}`
    assert.equal(await (await fetch(base)).text(), 'Sushi Buddy 9.9\n')
    assert.equal((await fetch(`${base}/claude`, { method: 'POST', body: '{"hook_event_name":"Stop"}' })).status, 204)
    assert.equal((await fetch(`${base}/claude`, { method: 'POST', body: 'not json' })).status, 400)
    assert.equal((await fetch(`${base}/fly`, { method: 'POST', body: 'Yo' })).status, 204)
    const tooBig = await fetch(`${base}/fly`, { method: 'POST', body: 'x'.repeat(70 * 1024) }).catch(() => ({ status: 413 }))
    assert.equal(tooBig.status, 413)
    assert.deepEqual(received, [['claude', 'Stop'], ['fly', 'Yo']])
    const taken = await listen(port, { version: '9.9', onClaude() {}, onFly() {} })
    assert.match(taken.error, /in use/)
  } finally {
    server.close()
  }
})

test('the system line reads as four signals; unknown parts count as not happening', () => {
  assert.deepEqual(parseSystem('1 5 0 1\r\n'), { focusProfile: 1, notificationState: 5, microphone: false, camera: true })
  assert.deepEqual(signalsFrom(parseSystem('1 5 0 1')), { focus: true, presenting: false, call: true })
  assert.deepEqual(signalsFrom(parseSystem('0 4 0 0')), { focus: false, presenting: true, call: false })
  assert.deepEqual(parseSystem('-1 -1'), { focusProfile: null, notificationState: null, microphone: null, camera: null })
  assert.deepEqual(signalsFrom(parseSystem('')), { focus: false, presenting: false, call: false })
})

test('every path is back on the straight line where the hover starts and ends', () => {
  for (const path of PATHS) {
    for (const direction of [1, -1]) {
      for (const [isFlyIn, u] of [[true, 0], [true, 1], [false, 0], [false, 1]]) {
        const { dx, dy, spin } = pathOffset(path, isFlyIn, u, direction)
        assert.ok(Math.abs(dx) < 1e-9 && Math.abs(dy) < 1e-9, `${path} ${isFlyIn ? 'in' : 'out'} at ${u}`)
        assert.ok(Math.abs(((spin % 360) + 360) % 360) < 1e-9 || Math.abs(((spin % 360) + 360) % 360 - 360) < 1e-9)
      }
    }
  }
})

test('no path jumps where the fly-in meets the hover or the hover meets the fly-out', () => {
  const canvas = { width: 1600, height: 900 }
  for (const path of PATHS) {
    const flight = previewFlight(canvas, path)
    for (const edge of [FLY_IN, FLY_IN + HOVER]) {
      const before = pose(flight, edge - 1e-6)
      const after = pose(flight, edge + 1e-6)
      assert.ok(Math.hypot(before.x - after.x, before.y - after.y) < 0.01, `${path} at ${edge}s`)
    }
  }
  assert.equal(DURATION, FLY_IN + HOVER + FLY_OUT)
})

test('the paths really leave the line somewhere', () => {
  const canvas = { width: 1600, height: 900 }
  for (const path of ['loop', 'bounce', 'zigzag']) {
    const flight = previewFlight(canvas, path)
    const classic = previewFlight(canvas, 'classic')
    const times = Array.from({ length: 72 }, (_, i) => i / 10)
    const strays = times.some(time => Math.abs(pose(flight, time).y - pose(classic, time).y) > 20)
    assert.ok(strays, path)
  }
})
