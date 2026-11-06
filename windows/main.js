const { app, BrowserWindow, Menu, Tray, nativeImage, screen } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

const { DURATION, previewFlight, randomFlight } = require('./flight')

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

function makeTray() {
  const icon = nativeImage.createFromPath(path.join(ASSETS, 'MenuBarIcon.png'))
  const side = process.platform === 'darwin' ? 18 : 32
  tray = new Tray(icon.resize({ width: side, height: side, quality: 'best' }))
  tray.setToolTip('Sushi Buddy')
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Motivate me', click: fly },
      { type: 'separator' },
      { label: 'Quit Sushi Buddy', role: 'quit' },
    ]),
  )
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
    const previewFile = argument('--preview')
    if (previewFile) {
      const moments = (argument('--at') ?? '0.9,3,5.9').split(',').map(Number)
      return preview(previewFile, moments)
    }
    if (process.platform === 'darwin') app.dock?.hide()
    makeTray()
    if (process.argv.includes('--fly')) fly()
  })
}
