// Turns Claude Code hook events into flights. The same rules as mac/Sources/SushiBuddy/Claude.swift.
//
// The hooks (claude-code/ in this repo) post every UserPromptSubmit, Stop and permission
// Notification here. A turn is timed from its prompt to its Stop, per session, so only
// the long ones are cheered.
const DAY = 24 * 60 * 60 * 1000

function projectName(cwd) {
  const parts = String(cwd ?? '').split(/[\\/]/).filter(Boolean)
  return parts[parts.length - 1] ?? ''
}

class ClaudeTracker {
  constructor() {
    this.started = new Map()
    this.lastHeard = null
  }

  /** The flight this event calls for, or null. Times are in milliseconds. */
  handle(event, now, settings) {
    this.lastHeard = now
    for (const [session, at] of this.started) if (now - at > DAY) this.started.delete(session)

    const session = String(event?.session_id ?? '')
    const project = projectName(event?.cwd)
    switch (event?.hook_event_name) {
      case 'UserPromptSubmit':
        this.started.set(session, now)
        return null
      case 'Stop': {
        const start = this.started.get(session)
        this.started.delete(session)
        if (!settings.claudeDone) return null
        const long = start === undefined ? settings.claudeMinMinutes === 0 : now - start >= settings.claudeMinMinutes * 60 * 1000
        return long ? { kind: 'claudeDone', project } : null
      }
      case 'Notification': {
        if (!settings.claudeNeedsYou) return null
        const type = event.notification_type
        const asking = type === 'permission_prompt' || (type == null && /permission/i.test(String(event.message ?? '')))
        return asking ? { kind: 'claudeNeedsYou', project } : null
      }
      default:
        return null
    }
  }
}

module.exports = { ClaudeTracker, projectName }
