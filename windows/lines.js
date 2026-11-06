// What the sushi says. The same rules as mac/Sources/SushiBuddy/Lines.swift.
//
// Resources/lines.json holds a list per occasion. A lines.json of your own (Settings →
// Edit Lines…) has the same shape; each list in it replaces the built-in one, and an
// occasion it leaves out keeps the built-in lines.
const CATEGORIES = [
  'anytime',
  'morning',
  'lateNight',
  'monday',
  'friday',
  'streak',
  'welcomeBack',
  'break',
  'claudeDone',
  'claudeNeedsYou',
  'pomodoroDone',
  'pomodoroBreakOver',
]
const FALLBACK = "You've got this!"

function usable(list) {
  if (!Array.isArray(list)) return null
  const lines = list.filter(line => typeof line === 'string' && line.trim() !== '')
  return lines.length ? lines : null
}

/** The built-in lines with the person's own on top, and what was wrong with theirs, if anything. */
function mergeLines(bundled, userText) {
  if (userText == null) return { lines: bundled, error: null }
  let parsed
  try {
    parsed = JSON.parse(userText)
  } catch (error) {
    return { lines: bundled, error: `Your lines.json isn't valid JSON (${error.message}), so the built-in lines are used.` }
  }
  // A plain list, the 1.3 shape, is lines for any time.
  if (Array.isArray(parsed)) parsed = { anytime: parsed }
  if (!parsed || typeof parsed !== 'object') {
    return { lines: bundled, error: 'Your lines.json should be an object of lists, so the built-in lines are used.' }
  }
  const lines = { ...bundled }
  for (const category of CATEGORIES) {
    const own = usable(parsed[category])
    if (own) lines[category] = own
  }
  return { lines, error: null }
}

/** The occasions that fit this moment: morning 5–11, late night 22–5, Monday, Friday. */
function occasions(date) {
  const hour = date.getHours()
  const found = []
  if (hour >= 5 && hour < 11) found.push('morning')
  if (hour >= 22 || hour < 5) found.push('lateNight')
  if (date.getDay() === 1) found.push('monday')
  if (date.getDay() === 5) found.push('friday')
  return found
}

function fill(text, { days, project }) {
  return text.replaceAll('{days}', String(days ?? 1)).replaceAll('{project}', project || 'your project')
}

/**
 * One line for a flight. `kind` is 'motivate' or an occasion of its own ('break', 'claudeDone', …).
 * A motivation is the streak line on the first one of a day from day 2 on; otherwise, with
 * occasions on, a coin toss between the lines for this moment and the anytime lines.
 */
function pickLine(kind, lines, { date, contextLines, streak, project }, random = Math.random) {
  const pick = list => list[Math.floor(random() * list.length)]
  let text
  if (kind === 'motivate') {
    if (streak && streak.firstToday && streak.days >= 2 && lines.streak?.length) {
      text = pick(lines.streak)
    } else {
      const fitting = contextLines ? occasions(date).flatMap(occasion => lines[occasion] ?? []) : []
      text = fitting.length && random() < 0.5 ? pick(fitting) : pick(lines.anytime ?? [])
    }
  } else {
    text = pick(lines[kind]?.length ? lines[kind] : lines.anytime ?? [])
  }
  return fill(text ?? FALLBACK, { days: streak?.days, project })
}

function dayKey(date) {
  const pad = number => String(number).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

/** Counts the days in a row with a motivation: the same day keeps it, the next day adds one, a gap starts over. */
function advanceStreak(streak, date) {
  const today = dayKey(date)
  if (streak?.lastDay === today) return { streak, firstToday: false }
  const yesterday = dayKey(new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1))
  const days = streak?.lastDay === yesterday ? (streak.days ?? 0) + 1 : 1
  return { streak: { days, lastDay: today }, firstToday: true }
}

module.exports = { CATEGORIES, advanceStreak, dayKey, fill, mergeLines, occasions, pickLine }
