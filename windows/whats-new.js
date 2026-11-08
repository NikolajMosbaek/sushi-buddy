// What's new in a version, for the menu's What's New: the highlights in whats-new.json, said by
// the sushi one at a time in the tour's bubble. The same rules as mac/Sources/SushiBuddy/WhatsNew.swift.
const { compareVersions, parseVersion } = require('./update')

const RELEASE_NOTES = 'https://github.com/NikolajMosbaek/sushi-buddy/releases'

/** The notes for `installed`: its own, or, for a version without any (a patch), the newest older ones. */
function pick(notes, installed) {
  if (!parseVersion(installed)) return null
  let best = null
  for (const [version, lines] of Object.entries(notes)) {
    if (!parseVersion(version) || !Array.isArray(lines) || lines.length === 0) continue
    if (compareVersions(version, installed) > 0) continue
    if (!best || compareVersions(version, best.version) > 0) best = { version, lines }
  }
  return best
}

/** `1.5.0` as 1.5: trailing zero parts dropped, down to major.minor. */
function display(version) {
  const parts = parseVersion(version)
  if (!parts) return String(version)
  while (parts.length > 2 && parts[parts.length - 1] === 0) parts.pop()
  return parts.join('.')
}

/** The bubble's steps, shaped like tour.js's: one per line, the last linking all the release notes. */
function steps(notes, installed) {
  const step = (id, text, link) => ({ id, text, switches: [], copies: null, showsLoop: false, link })
  const picked = pick(notes, installed)
  if (!picked) return [step('none', "I don't have notes for this version. All my release notes are on GitHub.", RELEASE_NOTES)]
  const name = display(picked.version)
  const last = picked.lines.length - 1
  return picked.lines.map((line, index) =>
    step(`new-${index + 1}`, index === 0 ? `New in ${name}: ${line}` : line, index === last ? RELEASE_NOTES : null),
  )
}

module.exports = { RELEASE_NOTES, pick, display, steps }
