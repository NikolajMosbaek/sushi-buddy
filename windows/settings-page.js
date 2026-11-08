// The Settings page: every control carries its setting's name in data-key, and every change
// goes straight to the app, which stores and applies it and answers with the new state.
const api = window.sushiSettings
const byId = id => document.getElementById(id)

const minutes = value => `${value} min`
const LABELS = {
  autoMotivateSeconds: {
    0: 'Off',
    900: 'Every 15 minutes',
    1800: 'Every 30 minutes',
    3600: 'Every hour',
    7200: 'Every 2 hours',
    14400: 'Every 4 hours',
  },
  breakReminderMinutes: value => (value === 0 ? 'Off' : `After ${value} min at the computer`),
  awayMinutes: value => `${value} min idle`,
  flightPath: { random: 'Any, at random', classic: 'Straight across', loop: 'Loop-the-loop', bounce: 'Bounce', zigzag: 'Zigzag' },
  sound: { off: 'Off', chime: 'Chime', whirr: 'Propeller whirr' },
  claudeMinMinutes: value => (value === 0 ? 'Any length' : minutes(value)),
  pomodoroFocusMinutes: minutes,
  pomodoroBreakMinutes: minutes,
}

function label(key, value, state) {
  if (key === 'hotkey') return state.hotkeyLabels[value] ?? value
  const labels = LABELS[key]
  return typeof labels === 'function' ? labels(value) : labels?.[value] ?? String(value)
}

function ago(time) {
  const seconds = Math.round((Date.now() - time) / 1000)
  if (seconds < 60) return 'just now'
  const minutesAgo = Math.round(seconds / 60)
  return minutesAgo < 60 ? `${minutesAgo} min ago` : `${Math.round(minutesAgo / 60)} h ago`
}

function render(state) {
  for (const control of document.querySelectorAll('[data-key]')) {
    const key = control.dataset.key
    if (control.tagName === 'SELECT') {
      if (control.options.length === 0) {
        for (const value of state.choices[key]) control.add(new Option(label(key, value, state), String(value)))
      }
      control.value = String(state.settings[key])
    } else {
      control.checked = state.settings[key] === true
    }
  }
  byId('launchAtLogin').checked = state.launchAtLogin
  byId('loginLabel').textContent = state.loginLabel
  byId('version').textContent = `Sushi Buddy ${state.versionLabel}`
  byId('claudeMinMinutes').disabled = !state.settings.claudeDone

  const { status } = state
  byId('hotkeyProblem').textContent = status.hotkeyProblem ?? ''
  byId('listenerProblem').textContent = status.listenerProblem ?? ''
  byId('lastSkip').textContent = status.lastSkip
    ? `Last skipped at ${new Date(status.lastSkip.at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}: ` +
      `${status.lastSkip.occasion}, because ${status.lastSkip.reason}.`
    : ''

  const lines = byId('linesStatus')
  lines.textContent = status.linesProblem ?? (state.hasOwnLines ? 'Using your lines.json.' : 'Using the built-in lines.')
  lines.className = status.linesProblem ? 'problem' : 'muted'
  if (state.streak) lines.textContent += ` Current streak: ${state.streak.days} day${state.streak.days === 1 ? '' : 's'}.`
  byId('revealLines').disabled = !state.hasOwnLines
  byId('resetLines').disabled = !state.hasOwnLines

  const button = byId('pomodoroButton')
  byId('pomodoroStatus').textContent = state.pomodoro ?? 'The sushi tells you when to break and when to start again.'
  button.textContent = state.pomodoro ? 'Stop' : 'Start'
  button.dataset.action = state.pomodoro ? 'stopPomodoro' : 'startPomodoro'

  byId('listenLabel').textContent = `Listen for Claude Code and scripts on 127.0.0.1:${state.port}`
  byId('claudeHeard').textContent = status.claudeLastHeard
    ? `Last heard from Claude Code ${ago(status.claudeLastHeard)}.`
    : 'Not heard from Claude Code since Sushi Buddy started.'
  byId('install').textContent = state.install
  byId('curl').textContent = `curl -d "Deployed! 🚀" http://127.0.0.1:${state.port}/fly`
}

for (const control of document.querySelectorAll('[data-key]')) {
  control.addEventListener('change', async () => {
    const key = control.dataset.key
    let value = control.type === 'checkbox' ? control.checked : control.value
    if (control.tagName === 'SELECT' && /^-?\d+$/.test(value)) value = Number(value)
    render(await api.set(key, value))
  })
}
byId('launchAtLogin').addEventListener('change', async event => render(await api.set('launchAtLogin', event.target.checked)))
for (const button of document.querySelectorAll('[data-action]')) {
  button.addEventListener('click', async () => render(await api.act(button.dataset.action)))
}

async function refreshSignals() {
  byId('signals').textContent = (await api.signals()).join('\n')
}

api.onState(render)
api.get().then(render)
refreshSignals()
setInterval(refreshSignals, 15000)
