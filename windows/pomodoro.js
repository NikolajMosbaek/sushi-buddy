// Focus, break, focus, …; every fourth break long (15 minutes) when long breaks are on.
// The same rules as mac/Sources/SushiBuddy/Pomodoro.swift. Times are in milliseconds.
const MINUTE = 60 * 1000
const LONG_BREAK_MINUTES = 15

function startPomodoro(now, settings) {
  return { phase: 'focus', endsAt: now + settings.pomodoroFocusMinutes * MINUTE, completed: 0 }
}

/** The phase after this one, and the occasion the sushi announces it with. */
function nextPhase(state, now, settings) {
  if (state.phase === 'focus') {
    const completed = state.completed + 1
    const long = settings.pomodoroLongBreaks && completed % 4 === 0
    const minutes = long ? LONG_BREAK_MINUTES : settings.pomodoroBreakMinutes
    return { state: { phase: long ? 'longBreak' : 'break', endsAt: now + minutes * MINUTE, completed }, line: 'pomodoroDone' }
  }
  return {
    state: { phase: 'focus', endsAt: now + settings.pomodoroFocusMinutes * MINUTE, completed: state.completed },
    line: 'pomodoroBreakOver',
  }
}

/** "Focus, 12 min left", for the menu. */
function describe(state, now) {
  const minutes = Math.max(1, Math.ceil((state.endsAt - now) / MINUTE))
  const name = state.phase === 'focus' ? 'Focus' : state.phase === 'longBreak' ? 'Long break' : 'Break'
  return `${name}, ${minutes} min left`
}

module.exports = { LONG_BREAK_MINUTES, describe, nextPhase, startPomodoro }
