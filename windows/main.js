const { app, BrowserWindow, Menu, Tray, dialog, nativeImage, screen, shell } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

const { DURATION, previewFlight, randomFlight } = require('./flight')
const { focusProfile, isFocused } = require('./focus')
const { check: checkForUpdate } = require('./update')

const ASSETS = path.join(__dirname, 'assets')
const OVERLAY = path.join(__dirname, 'overlay.html')
const lines = JSON.parse(fs.readFileSync(path.join(ASSETS, 'motivation.json'), 'utf8'))

// Held until each flight lands: a window or tray that is dropped is collected mid-flight.
let tray
const flights = new Set()

function fly() {
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint())
  const { x, y, width, height } = display.bounds
  const flight = randomFlight({ width, height }, lines)

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
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true },
  })
  overlay.setAlwaysOnTop(true, 'screen-saver')
  overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  overlay.setIgnoreMouseEvents(true)
  flights.add(overlay)

  overlay.once('ready-to-show', () => {
    overlay.showInactive()
    setTimeout(() => {
      flights.delete(overlay)
      overlay.destroy()
    }, (DURATION + 0.3) * 1000)
  })
  overlay.loadFile(OVERLAY, { query: { flight: JSON.stringify(flight) } })
}

// The same presets as mac/Sources/SushiBuddy/AutoMotivate.swift, in seconds (0 = off).
const AUTO_MOTIVATE_PRESETS = [
  ['Off', 0],
  ['Every 15 minutes', 15 * 60],
  ['Every 30 minutes', 30 * 60],
  ['Every hour', 60 * 60],
  ['Every 2 hours', 2 * 60 * 60],
  ['Every 4 hours', 4 * 60 * 60],
]
let autoMotivateTimer

function settingsFile() {
  return path.join(app.getPath('userData'), 'settings.json')
}

function readSettings() {
  try {
    return JSON.parse(fs.readFileSync(settingsFile(), 'utf8'))
  } catch {
    return {}
  }
}

function autoMotivateSeconds() {
  const seconds = Number(readSettings().autoMotivateSeconds)
  return Number.isFinite(seconds) && seconds > 0 ? seconds : 0
}

// (Re)starts the countdown from now, so a change takes effect at once.
// A turn that comes round during a Focus is skipped, not saved for later.
function startAutoMotivate() {
  clearInterval(autoMotivateTimer)
  const seconds = autoMotivateSeconds()
  autoMotivateTimer =
    seconds > 0
      ? setInterval(async () => {
          if (!(await isFocused())) fly()
        }, seconds * 1000)
      : undefined
}

function setAutoMotivate(seconds) {
  fs.mkdirSync(app.getPath('userData'), { recursive: true })
  fs.writeFileSync(settingsFile(), JSON.stringify({ ...readSettings(), autoMotivateSeconds: seconds }, null, 2))
  startAutoMotivate()
}

// A newer release found by the quiet checks: the menu then offers it in place of the check.
let availableUpdate

// Quietly at launch and once a day; nothing installs by itself.
function startQuietUpdateChecks() {
  const quietCheck = async () => {
    const result = await checkForUpdate(app.getVersion())
    if (result.status === 'failed') return
    availableUpdate = result.status === 'available' ? result : undefined
    refreshMenu()
  }
  quietCheck()
  setInterval(quietCheck, 24 * 60 * 60 * 1000)
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

function refreshMenu() {
  const current = autoMotivateSeconds()
  const update = availableUpdate
    ? { label: `Update to ${availableUpdate.latest}…`, click: () => shell.openExternal(availableUpdate.url) }
    : { label: 'Check for Updates…', click: checkAndTell }
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Motivate me', click: fly },
      {
        label: 'Auto-motivate',
        submenu: AUTO_MOTIVATE_PRESETS.map(([label, seconds]) => ({
          label,
          type: 'radio',
          checked: seconds === current,
          click: () => {
            setAutoMotivate(seconds)
            refreshMenu()
          },
        })),
      },
      {
        label: process.platform === 'win32' ? 'Start with Windows' : 'Launch at Login',
        type: 'checkbox',
        checked: app.getLoginItemSettings().openAtLogin,
        click: item => {
          app.setLoginItemSettings({ openAtLogin: item.checked })
          refreshMenu()
        },
      },
      { type: 'separator' },
      update,
      { type: 'separator' },
      { label: 'Quit Sushi Buddy', role: 'quit' },
    ]),
  )
}

function makeTray() {
  const icon = nativeImage.createFromPath(path.join(ASSETS, 'MenuBarIcon.png'))
  const side = process.platform === 'darwin' ? 18 : 32
  tray = new Tray(icon.resize({ width: side, height: side, quality: 'best' }))
  tray.setToolTip('Sushi Buddy')
  refreshMenu()
  // On Windows a left click on a tray icon opens nothing by default: make it fly.
  if (process.platform === 'win32') tray.on('click', fly)
}

// --preview <file.png> [--at 0.9,3,5.9]: renders moments of a flight to PNGs and quits.
async function preview(file, moments) {
  const canvas = { width: 900, height: 420 }
  const window = new BrowserWindow({
    ...canvas,
    show: false,
    frame: false,
    transparent: true,
    webPreferences: { offscreen: true },
  })
  for (const at of moments) {
    await window.loadFile(OVERLAY, { query: { flight: JSON.stringify(previewFlight(canvas)), at: String(at) } })
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
  })
  // Overlays come and go; the app lives in the tray until Quit.
  app.on('window-all-closed', () => {})

  app.whenReady().then(() => {
    // A GUI .exe has no console to print to, so on Windows the answer is a dialog.
    if (process.argv.includes('--focus-status')) {
      return focusProfile().then(async profile => {
        const state = profile === null ? 'unreadable' : profile === 0 ? 'off' : 'on'
        const text = `Do not disturb / Focus assist: ${state} (profile ${profile ?? '-'}; 0 = off).`
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
      return preview(previewFile, moments)
    }
    if (process.platform === 'darwin') app.dock?.hide()
    makeTray()
    startAutoMotivate()
    startQuietUpdateChecks()
    if (process.argv.includes('--fly')) fly()
  })
}
