// When automatic flights hold off, when you've come back, and when a break is due.
// The same rules as mac/Sources/SushiBuddy/Presence.swift.

/** The first reason that holds and is switched on, or null when an automatic flight may go. */
function quietReason(settings, signals) {
  if (settings.quietWhenAway && signals.away) return 'away'
  if (settings.quietDuringFocus && signals.focus) return 'focus'
  if (settings.quietOnCalls && signals.call) return 'call'
  if (settings.quietWhenPresenting && signals.presenting) return 'presenting'
  return null
}

const QUIET_REASONS = {
  away: 'you were away',
  focus: 'a Focus was on',
  call: 'you were on a call',
  presenting: 'you were presenting',
}

function isAway({ idleSeconds, locked }, awayMinutes) {
  return locked || idleSeconds >= awayMinutes * 60
}

/** Notices the step from away to back. Times are in milliseconds. */
function presenceTick(state, { now, away, idleSeconds }) {
  if (away) return { state: { awaySince: state.awaySince ?? now - idleSeconds * 1000 }, cameBack: false }
  if (state.awaySince != null) return { state: { awaySince: null }, cameBack: true, awayFor: now - state.awaySince }
  return { state, cameBack: false }
}

/** Five minutes without touching anything counts as a break. */
const BREAK_SECONDS = 5 * 60

/** Counts time at the computer since the last break; a reminder starts the count again. */
function breakTick(state, { now, idleSeconds, intervalMinutes }) {
  if (idleSeconds >= BREAK_SECONDS) return { state: { activeSince: now }, remind: false }
  if (intervalMinutes > 0 && now - state.activeSince >= intervalMinutes * 60 * 1000) {
    return { state: { activeSince: now }, remind: true }
  }
  return { state, remind: false }
}

module.exports = { BREAK_SECONDS, QUIET_REASONS, breakTick, isAway, presenceTick, quietReason }
