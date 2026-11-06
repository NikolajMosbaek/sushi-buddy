const { app, BrowserWindow, Menu, Tray, clipboard, dialog, globalShortcut, ipcMain, nativeImage, powerMonitor, screen, shell } =
  require('electron')
const fs = require('node:fs')
const path = require('node:path')

const { DURATION, previewFlight, randomFlight } = require('./flight')
const { CHOICES, normalize, readFile, update, writeFile } = require('./settings')
const { advanceStreak, mergeLines, pickLine } = require('./lines')
const { QUIET_REASONS, breakTick, isAway, presenceTick, quietReason } = require('./presence')
const { describe: describePomodoro, nextPhase, startPomodoro } = require('./pomodoro')
const { ClaudeTracker } = require('./claude')
const { PORT, listen } = require('./listener')
const { readSystem, signalsFrom } = require('./system')
const { check: checkForUpdate } = require('./update')

const ASSETS = path.join(__dirname, 'assets')
const OVERLAY = path.join(__dirname, 'overlay.html')
const SETTINGS_PAGE = path.join(__dirname, 'settings.html')
const BUNDLED_LINES = JSON.parse(fs.readFileSync(path.join(ASSETS, 'lines.json'), 'utf8'))
const INSTALL_HOOKS = 'claude plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy'
const HOTKEY_LABELS = {
  off: 'Off',
  'Control+Alt+Shift+S': 'Ctrl+Alt+Shift+S',
  'Control+Alt+S': 'Ctrl+Alt+S',
  'Control+Alt+Shift+M': 'Ctrl+Alt+Shift+M',
}

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json')
const userLinesFile = () => path.join(app.getPath('userData'), 'lines.json')

let settings
// What Settings shows besides the choices: why things didn't happen, and when Claude was last heard.
const status = { lastSkip: null, linesProblem: null, hotkeyProblem: null, listenerProblem: null, claudeLastHeard: null }

// Held until each flight lands: a window or tray that is dropped is collected mid-flight.
let tray
let settingsWindow
const flights = new Set()

// MARK: Flying

function launch(message) {
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint())
  const { x, y, width, height } = display.bounds
  const flight = randomFlight({ width, height }, message, settings.flightPath)

  const overlay = new BrowserWindow({
    x,
    y,
    width,
    height,
    show: false,
    frame: false,
    transparent: true,
    hasShadow: false,
    resizable: false,
    movable: false,
    focusable: false,
    skipTaskbar: true,
    fullscreenable: false,
    alwaysOnTop: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(__dirname, 'overlay-preload.js'),
      autoplayPolicy: 'no-user-gesture-required',
    },
  })
  overlay.setAlwaysOnTop(true, 'screen-saver')
  overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  // With petting on, the overlay still hears the mouse moving, so it can take clicks while it's over the sushi.
  overlay.setIgnoreMouseEvents(true, { forward: settings.petting })
  flights.add(overlay)

  overlay.once('ready-to-show', () => {
    overlay.showInactive()
    setTimeout(() => {
      flights.delete(overlay)
      overlay.destroy()
    }, (DURATION + 0.3) * 1000)
  })
  overlay.loadFile(OVERLAY, {
    query: { flight: JSON.stringify(flight), petting: settings.petting ? '1' : '0', sound: settings.sound },
  })
}

/**
 * Flies now. `occasion` is 'motivate' or one of the line file's occasions. An automatic flight
 * first checks the quiet rules, and a skip is shown in Settings so a quiet app doesn't look broken.
 */
async function fly(occasion = 'motivate', { automatic = false, project, message } = {}) {
  if (automatic) {
    const reason = quietReason(settings, await quietSignals())
    if (reason) {
      status.lastSkip = { occasion, reason: QUIET_REASONS[reason], at: Date.now() }
      sendState()
      return
    }
  }
  launch(message ?? lineFor(occasion, project))
}

function loadLines() {
  let own = null
  try {
    own = fs.readFileSync(userLinesFile(), 'utf8')
  } catch {
    // No lines of your own.
  }
  const { lines, error } = mergeLines(BUNDLED_LINES, own)
  status.linesProblem = error
  return lines
}

function lineFor(occasion, project) {
  let streak = null
  if (occasion === 'motivate') {
    const stored = readFile(settingsFile())
    const advanced = advanceStreak(stored.streak, new Date())
    writeFile(settingsFile(), { ...stored, streak: advanced.streak })
    if (settings.streaks) streak = { days: advanced.streak.days, firstToday: advanced.firstToday }
  }
  return pickLine(occasion, loadLines(), { date: new Date(), contextLines: settings.contextLines, streak, project })
}

// MARK: Quiet rules

function idle() {
  const seconds = powerMonitor.getSystemIdleTime()
  const locked = powerMonitor.getSystemIdleState(settings.awayMinutes * 60) === 'locked'
  return { idleSeconds: seconds, locked }
}

/** The signals the quiet rules need; PowerShell runs only when a rule that needs it is on. */
async function quietSignals() {
  const away = isAway(idle(), settings.awayMinutes)
  const needsSystem = settings.quietDuringFocus || settings.quietOnCalls || settings.quietWhenPresenting
  const system = needsSystem ? signalsFrom(await readSystem()) : { focus: false, call: false, presenting: false }
  return { away, ...system }
}

// MARK: On their own

let autoMotivateTimer
let watchTimer
let presence = { awaySince: null }
let breaks = { activeSince: Date.now() }

// Counted from now, so a change takes effect at once. A turn during a quiet time is skipped, not saved.
function restartAutoMotivate() {
  clearInterval(autoMotivateTimer)
  autoMotivateTimer =
    settings.autoMotivateSeconds > 0
      ? setInterval(() => fly('motivate', { automatic: true }), settings.autoMotivateSeconds * 1000)
      : undefined
}

/** Every few seconds: have you come back, and is a break due? */
function watch() {
  const now = Date.now()
  const { idleSeconds, locked } = idle()
  const away = isAway({ idleSeconds, locked }, settings.awayMinutes)
  const back = presenceTick(presence, { now, away, idleSeconds })
  presence = back.state
  if (back.cameBack && settings.welcomeBack && back.awayFor >= settings.awayMinutes * 60 * 1000) {
    fly('welcomeBack', { automatic: true })
  }
  const due = breakTick(breaks, { now, idleSeconds, intervalMinutes: settings.breakReminderMinutes })
  breaks = due.state
  if (due.remind) fly('break', { automatic: true })
}

// MARK: Pomodoro

let pomodoro = null
let pomodoroTimer

function schedulePomodoro() {
  clearTimeout(pomodoroTimer)
  if (!pomodoro) return
  pomodoroTimer = setTimeout(
    () => {
      const next = nextPhase(pomodoro, Date.now(), settings)
      pomodoro = next.state
      fly(next.line)
      schedulePomodoro()
      refreshMenu()
      sendState()
    },
    Math.max(0, pomodoro.endsAt - Date.now()),
  )
}

function setPomodoro(running) {
  pomodoro = running ? startPomodoro(Date.now(), settings) : null
  schedulePomodoro()
  refreshMenu()
  sendState()
}

// MARK: Shortcut, listener, updates

function registerHotkey() {
  globalShortcut.unregisterAll()
  status.hotkeyProblem = null
  if (settings.hotkey === 'off') return
  if (!globalShortcut.register(settings.hotkey, () => fly())) {
    status.hotkeyProblem = `${HOTKEY_LABELS[settings.hotkey]} is taken by another app; pick another.`
  }
}

const claude = new ClaudeTracker()
let listener

async function startListening() {
  if (listener) return
  const result = await listen(PORT, {
    version: app.getVersion(),
    onClaude: event => {
      status.claudeLastHeard = Date.now()
      const cheer = claude.handle(event, Date.now(), settings)
      if (cheer) fly(cheer.kind, { automatic: true, project: cheer.project })
      sendState()
    },
    onFly: message => fly('motivate', { message: message ?? undefined }),
  })
  listener = result.server
  status.listenerProblem = result.error ?? null
  sendState()
}

function stopListening() {
  listener?.close()
  listener = undefined
  status.listenerProblem = null
}

// A newer release found by the quiet checks: the menu then offers it in place of the check.
let availableUpdate
let updateTimer

// Quietly at launch and once a day; nothing installs by itself.
function startQuietUpdateChecks() {
  const quietCheck = async () => {
    const result = await checkForUpdate(app.getVersion())
    if (result.status === 'failed') return
    availableUpdate = result.status === 'available' ? result : undefined
    refreshMenu()
  }
  clearInterval(updateTimer)
  quietCheck()
  updateTimer = setInterval(quietCheck, 24 * 60 * 60 * 1000)
}

function stopQuietUpdateChecks() {
  clearInterval(updateTimer)
  updateTimer = undefined
}

async function checkAndTell() {
  const result = await checkForUpdate(app.getVersion())
  availableUpdate = result.status === 'available' ? result : undefined
  refreshMenu()
  if (result.status === 'available') {
    const { response } = await dialog.showMessageBox({
      title: 'Sushi Buddy',
      message: `Sushi Buddy ${result.latest} is available`,
      detail: `You have ${app.getVersion()}. The download opens in your browser.`,
      buttons: ['Download', 'Later'],
      defaultId: 0,
      cancelId: 1,
    })
    if (response === 0) shell.openExternal(result.url)
  } else if (result.status === 'up-to-date') {
    await dialog.showMessageBox({
      title: 'Sushi Buddy',
      message: 'Sushi Buddy is up to date',
      detail: `${app.getVersion()} is the latest version.`,
    })
  } else {
    await dialog.showMessageBox({ type: 'warning', title: 'Sushi Buddy', message: "Couldn't check for updates", detail: result.reason })
  }
}

// MARK: Settings

/** Applies what changed (everything, at launch). */
function apply(old) {
  const now = settings
  if (!old || old.autoMotivateSeconds !== now.autoMotivateSeconds) restartAutoMotivate()
  if (!old || old.breakReminderMinutes !== now.breakReminderMinutes) breaks = { activeSince: Date.now() }
  if (!old || old.hotkey !== now.hotkey) registerHotkey()
  if (!old || old.listen !== now.listen) now.listen ? startListening() : stopListening()
  if (!old || old.checkForUpdates !== now.checkForUpdates) now.checkForUpdates ? startQuietUpdateChecks() : stopQuietUpdateChecks()
}

function state() {
  loadLines()
  return {
    settings,
    choices: CHOICES,
    hotkeyLabels: HOTKEY_LABELS,
    status,
    launchAtLogin: app.getLoginItemSettings().openAtLogin,
    loginLabel: process.platform === 'win32' ? 'Start with Windows' : 'Launch at login',
    hasOwnLines: fs.existsSync(userLinesFile()),
    streak: readFile(settingsFile()).streak ?? null,
    pomodoro: pomodoro ? describePomodoro(pomodoro, Date.now()) : null,
    port: PORT,
    install: INSTALL_HOOKS,
    version: app.getVersion(),
  }
}

function sendState() {
  if (settingsWindow && !settingsWindow.isDestroyed()) settingsWindow.webContents.send('settings:state', state())
}

ipcMain.handle('settings:get', () => state())

ipcMain.handle('settings:set', (_event, key, value) => {
  if (key === 'launchAtLogin') {
    app.setLoginItemSettings({ openAtLogin: value === true })
  } else {
    const old = settings
    settings = update(settingsFile(), key, value)
    apply(old)
  }
  refreshMenu()
  return state()
})

ipcMain.handle('settings:action', async (_event, action) => {
  switch (action) {
    case 'tryIt':
      fly()
      break
    case 'editLines':
      if (!fs.existsSync(userLinesFile())) {
        fs.mkdirSync(path.dirname(userLinesFile()), { recursive: true })
        fs.copyFileSync(path.join(ASSETS, 'lines.json'), userLinesFile())
      }
      await shell.openPath(userLinesFile())
      break
    case 'revealLines':
      shell.showItemInFolder(userLinesFile())
      break
    case 'resetLines':
      await shell.trashItem(userLinesFile()).catch(() => fs.rmSync(userLinesFile(), { force: true }))
      break
    case 'startPomodoro':
      setPomodoro(true)
      break
    case 'stopPomodoro':
      setPomodoro(false)
      break
    case 'copyInstall':
      clipboard.writeText(INSTALL_HOOKS)
      break
  }
  return state()
})

/** One line per signal, for "Right now" in Settings and for --status. */
async function describeSignals() {
  const { idleSeconds, locked } = idle()
  const system = await readSystem()
  const known = value => (value == null ? 'unreadable' : value)
  return [
    `Do not disturb / Focus assist: ${system.focusProfile == null ? 'unreadable' : system.focusProfile === 0 ? 'off' : 'on'} (profile ${known(system.focusProfile)})`,
    `Idle: ${idleSeconds} s, screen ${locked ? 'locked' : 'unlocked'} (away after ${settings.awayMinutes} min)`,
    `Microphone: ${system.microphone == null ? 'unreadable' : system.microphone ? 'in use' : 'not in use'}, camera: ${system.camera == null ? 'unreadable' : system.camera ? 'in use' : 'not in use'}`,
    `Full screen or presenting: ${system.notificationState == null ? 'unreadable' : [2, 3, 4].includes(system.notificationState) ? 'yes' : 'no'} (state ${known(system.notificationState)})`,
  ]
}

ipcMain.handle('settings:signals', () => describeSignals())

function settingsWindowOptions(extra = {}) {
  return {
    width: 640,
    height: 820,
    title: 'Sushi Buddy Settings',
    autoHideMenuBar: true,
    resizable: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(__dirname, 'settings-preload.js'),
      ...extra,
    },
  }
}

function showSettings() {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.show()
    settingsWindow.focus()
    return
  }
  settingsWindow = new BrowserWindow({ ...settingsWindowOptions(), icon: path.join(ASSETS, 'MenuBarIcon.png') })
  settingsWindow.removeMenu()
  settingsWindow.loadFile(SETTINGS_PAGE)
}

// MARK: Menu

let menuTimer

function refreshMenu() {
  if (!tray) return
  const update = availableUpdate
    ? { label: `Update to ${availableUpdate.latest}…`, click: () => shell.openExternal(availableUpdate.url) }
    : { label: 'Check for Updates…', click: checkAndTell }
  const pomodoroItem = pomodoro
    ? { label: `Stop Pomodoro (${describePomodoro(pomodoro, Date.now())})`, click: () => setPomodoro(false) }
    : { label: 'Start Pomodoro', click: () => setPomodoro(true) }
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Motivate me', click: () => fly() },
      pomodoroItem,
      { type: 'separator' },
      { label: 'Settings…', click: showSettings },
      update,
      { type: 'separator' },
      { label: 'Quit Sushi Buddy', role: 'quit' },
    ]),
  )
  // Keeps the minutes left in the Pomodoro item current.
  clearTimeout(menuTimer)
  if (pomodoro) menuTimer = setTimeout(refreshMenu, 30 * 1000)
}

function makeTray() {
  const icon = nativeImage.createFromPath(path.join(ASSETS, 'MenuBarIcon.png'))
  const side = process.platform === 'darwin' ? 18 : 32
  tray = new Tray(icon.resize({ width: side, height: side, quality: 'best' }))
  tray.setToolTip('Sushi Buddy')
  refreshMenu()
  // On Windows a left click on a tray icon opens nothing by default: make it fly.
  if (process.platform === 'win32') tray.on('click', () => fly())
}

// MARK: Previews

// --preview <file.png> [--at 0.9,3,5.9] [--path loop] [--pets 2.5]: renders moments of a flight to PNGs and quits.
async function preview(file, moments, flightPath, pets) {
  const canvas = { width: 900, height: 420 }
  const window = new BrowserWindow({
    ...canvas,
    show: false,
    frame: false,
    transparent: true,
    webPreferences: { offscreen: true, preload: path.join(__dirname, 'overlay-preload.js') },
  })
  for (const at of moments) {
    await window.loadFile(OVERLAY, {
      query: { flight: JSON.stringify(previewFlight(canvas, flightPath)), at: String(at), pets: pets.join(',') },
    })
    await new Promise(resolve => setTimeout(resolve, 400))
    // An offscreen page that looks the same as the last one paints nothing new,
    // and capturePage would wait for that paint for ever: ask for one.
    window.webContents.invalidate()
    const image = await window.webContents.capturePage()
    const out = file.replace(/\.png$/, '') + `-${at}s.png`
    fs.writeFileSync(out, image.toPNG())
    console.log(out)
  }
  app.quit()
}

// --preview-settings <folder>: renders the Settings page to settings.png and quits.
async function previewSettings(folder) {
  const window = new BrowserWindow({ ...settingsWindowOptions({ offscreen: true }), show: false, height: 2200 })
  await window.loadFile(SETTINGS_PAGE)
  await new Promise(resolve => setTimeout(resolve, 1500))
  window.webContents.invalidate()
  const image = await window.webContents.capturePage()
  const out = path.join(folder, 'settings.png')
  fs.writeFileSync(out, image.toPNG())
  console.log(out)
  app.quit()
}

function argument(name) {
  const at = process.argv.indexOf(name)
  return at === -1 ? undefined : process.argv[at + 1]
}

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  // A second launch (a shortcut with --fly) reaches the running app.
  app.on('second-instance', (_event, argv) => {
    if (argv.includes('--fly')) fly()
    if (argv.includes('--settings')) showSettings()
  })
  // Overlays and Settings come and go; the app lives in the tray until Quit.
  app.on('window-all-closed', () => {})
  app.on('will-quit', () => globalShortcut.unregisterAll())

  ipcMain.on('overlay:over-sushi', (event, over) => {
    BrowserWindow.fromWebContents(event.sender)?.setIgnoreMouseEvents(!over, { forward: true })
  })

  app.whenReady().then(() => {
    settings = normalize(readFile(settingsFile()))

    // A GUI .exe has no console to print to, so on Windows the answer is a dialog.
    if (process.argv.includes('--status')) {
      return describeSignals().then(async lines => {
        const text = lines.join('\n')
        console.log(text)
        if (process.platform === 'win32') await dialog.showMessageBox({ title: 'Sushi Buddy', message: text })
        app.quit()
      })
    }
    // --launch-at-login on|off: for setting it up from a script (on Windows: the Run registry key).
    const launchAtLogin = argument('--launch-at-login')
    if (launchAtLogin === 'on' || launchAtLogin === 'off') {
      app.setLoginItemSettings({ openAtLogin: launchAtLogin === 'on' })
      console.log(`Launch at Login: ${app.getLoginItemSettings().openAtLogin ? 'on' : 'off'}`)
      app.quit()
      return
    }
    if (process.argv.includes('--check-updates')) {
      return checkForUpdate(app.getVersion()).then(result => {
        console.log(`Installed ${app.getVersion()}: ${JSON.stringify(result)}`)
        app.quit()
      })
    }
    const previewFile = argument('--preview')
    if (previewFile) {
      const moments = (argument('--at') ?? '0.9,3,5.9').split(',').map(Number)
      const pets = argument('--pets') ? argument('--pets').split(',').map(Number) : []
      return preview(previewFile, moments, argument('--path') ?? 'classic', pets)
    }
    const settingsFolder = argument('--preview-settings')
    if (settingsFolder) return previewSettings(settingsFolder)

    if (process.platform === 'darwin') app.dock?.hide()
    makeTray()
    apply(null)
    watchTimer = setInterval(watch, 5000)
    if (process.argv.includes('--fly')) fly()
    if (process.argv.includes('--settings')) showSettings()
  })
}
