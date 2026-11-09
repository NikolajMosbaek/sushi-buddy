// Renders the seasonal sushis in Art/seasonal/ to transparent PNGs in Resources/, lined up with the
// classic sushi, and writes Resources/sushis.json: each sushi's name, images and the points its
// animations need (where the pompom hangs, where a can's mouth is, ...).
//
// Run it with the Electron the Windows app already has (Chromium draws the SVGs: masks, blend modes
// and the embedded photos all render as in a browser):
//
//   cd windows && npx electron ../Art/render-sushis.js
//
// Lining up: the salmon (the #FC9E24 shape every sushi has) is scaled to the classic salmon's width
// and placed with its centre and bottom where the classic one's are. Everything is measured in the
// classic art's units (its viewBox is 60×60); a seasonal image covers the square STAGE, which leaves
// room around that 60×60 frame for umbrellas, cans, ears and baskets.
const { app, BrowserWindow } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

app.commandLine.appendSwitch('force-device-scale-factor', '1')

const art = __dirname
const resources = path.join(__dirname, '..', 'Resources')
const STAGE = { min: -20, size: 100 }
const PIXELS = 1200

// `drop`: elements left out (the classic sushi flies without its `?` too). `layers`: elements drawn
// in an image of their own, so they can move on their own. `points`: named spots, measured on what an
// element (or a layer) draws: its middle, or with `edge: 'top'` where it starts. Elements are picked
// by their tag and a test on their box, in the SVG's own units.
const sushis = [
  { id: 'classic', name: 'Classic Sushi' },
  { id: 'rainy', name: 'Rainy Day Sushi', file: 'rainy.svg' },
  {
    id: 'jday',
    name: 'J-Day Sushi',
    file: 'jday.svg',
    points: { can: { find: 'image', edge: 'top' } },
  },
  {
    id: 'santa',
    name: 'Santa Sushi',
    file: 'santa.svg',
    drop: box => box.x > 55.5 && box.y > 18 && box.x + box.width < 73 && box.y + box.height < 42,
    layers: { pompom: { find: 'circle', test: box => Math.abs(box.x + box.width / 2 - 51.94) < 0.5 } },
    points: { pompomTop: { layer: 'pompom', edge: 'top' } },
  },
  {
    id: 'bunny',
    name: 'Easter Bunny Sushi',
    file: 'bunny.svg',
    points: { basket: { find: 'image', which: 'last', edge: 'top' } },
  },
  {
    id: 'metalhead',
    name: 'Metalhead Sushi',
    file: 'metalhead.svg',
    points: { can: { find: 'image', which: 'last', edge: 'top' } },
  },
]

const page = `<!doctype html><html><head><style>
html, body { margin: 0; background: transparent; overflow: hidden; }
</style></head><body><div id="host"></div></body></html>`

// Runs in the page. Measures the sushi, then draws the requested part of it on the stage.
function inPage(svgText, plan, stage, pixels) {
  const host = document.getElementById('host')
  host.innerHTML = svgText
  const svg = host.querySelector('svg')
  const [, , vw, vh] = svg.getAttribute('viewBox').split(/[\s,]+/).map(Number)
  const scale = 10
  svg.setAttribute('width', vw * scale)
  svg.setAttribute('height', vh * scale)
  const origin = svg.getBoundingClientRect()
  const boxOf = element => {
    const rect = element.getBoundingClientRect()
    return { x: (rect.left - origin.left) / scale, y: (rect.top - origin.top) / scale, width: rect.width / scale, height: rect.height / scale }
  }
  const drawn = [...svg.querySelectorAll('path, rect, circle, ellipse, image, use, g')].filter(
    element => !element.closest('defs, mask, clipPath, pattern'),
  )
  const salmon = drawn.find(element => (element.getAttribute('fill') ?? '').toUpperCase() === '#FC9E24')
  const shapes = drawn.filter(element => element.tagName !== 'g')
  const pick = (find, test, which) => {
    const matches = shapes.filter(
      element =>
        (!find || element.tagName === find || (find === 'image' && /url\(#pattern/.test(element.getAttribute('fill') ?? ''))) &&
        (!test || test(boxOf(element))),
    )
    return which === 'last' ? matches.slice(-1) : matches.slice(0, 1)
  }
  return { svg, boxOf, salmon: boxOf(salmon), pick, shapes, vw, vh }
}

async function render(win, sushi, classicSalmon) {
  const svgText = fs.readFileSync(path.join(art, 'seasonal', sushi.file), 'utf8')
  const plan = {
    drop: sushi.drop?.toString(),
    layers: Object.fromEntries(Object.entries(sushi.layers ?? {}).map(([name, layer]) => [name, { ...layer, test: layer.test?.toString() }])),
    points: sushi.points ?? {},
  }
  // Measure, then work out where the sushi goes on the stage.
  const measured = await win.webContents.executeJavaScript(`(() => {
    const inPage = ${inPage.toString()};
    const m = inPage(${JSON.stringify(svgText)}, null, ${JSON.stringify(STAGE)}, ${PIXELS});
    const plan = ${JSON.stringify(plan)};
    const fn = text => text && eval('(' + text + ')');
    const tag = (element, label) => element.setAttribute('data-part', label);
    const drop = fn(plan.drop);
    if (drop) for (const element of m.shapes) if (drop(m.boxOf(element))) tag(element, 'drop');
    for (const [name, layer] of Object.entries(plan.layers)) {
      for (const element of m.pick(layer.find, fn(layer.test), layer.which)) tag(element, 'layer-' + name);
    }
    for (const [name, point] of Object.entries(plan.points)) {
      if (point.layer) continue;
      for (const element of m.pick(point.find, null, point.which)) tag(element, 'point-' + name);
    }
    let top = Infinity, left = Infinity, right = -Infinity, bottom = -Infinity;
    for (const element of m.shapes) {
      if (element.getAttribute('data-part') === 'drop') continue;
      const box = m.boxOf(element);
      if (box.width === 0 && box.height === 0) continue;
      top = Math.min(top, box.y); left = Math.min(left, box.x);
      right = Math.max(right, box.x + box.width); bottom = Math.max(bottom, box.y + box.height);
    }
    window.__sushi = m.svg.outerHTML;
    return { salmon: m.salmon, extent: { top, left, right, bottom }, vw: m.vw, vh: m.vh };
  })()`)

  const k = classicSalmon.width / measured.salmon.width
  const dx = classicSalmon.x + classicSalmon.width / 2 - k * (measured.salmon.x + measured.salmon.width / 2)
  const dy = classicSalmon.y + classicSalmon.height - k * (measured.salmon.y + measured.salmon.height)
  const extent = {
    top: round(dy + k * measured.extent.top),
    left: round(dx + k * measured.extent.left),
    right: round(dx + k * measured.extent.right),
    bottom: round(dy + k * measured.extent.bottom),
  }
  const end = STAGE.min + STAGE.size
  if (extent.top < STAGE.min || extent.left < STAGE.min || extent.right > end || extent.bottom > end) {
    throw new Error(`${sushi.id} reaches outside the stage: ${JSON.stringify(extent)}`)
  }

  // Draws one part on the stage: 'body' (all but the layers and what's dropped), 'layer-<name>' or
  // 'point-<name>' (that element alone).
  const draw = async part => {
    await win.webContents.executeJavaScript(`(() => {
      const host = document.getElementById('host');
      host.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="${PIXELS}" height="${PIXELS}" viewBox="${STAGE.min} ${STAGE.min} ${STAGE.size} ${STAGE.size}"></svg>';
      const stage = host.firstChild;
      const holder = document.createElement('div');
      holder.innerHTML = window.__sushi;
      const sushi = holder.firstChild;
      sushi.setAttribute('x', ${dx}); sushi.setAttribute('y', ${dy});
      sushi.setAttribute('width', ${measured.vw * k}); sushi.setAttribute('height', ${measured.vh * k});
      sushi.setAttribute('overflow', 'visible');
      const part = ${JSON.stringify(part)};
      for (const element of sushi.querySelectorAll('[data-part]')) {
        const label = element.getAttribute('data-part');
        const keep = part === 'body' ? label !== 'drop' && !label.startsWith('layer-') : label === part;
        if (!keep) element.remove();
      }
      if (part !== 'body') {
        for (const element of sushi.querySelectorAll('path, rect, circle, ellipse, image, use')) {
          if (element.closest('defs, mask, clipPath, pattern')) continue;
          if (element.getAttribute('data-part') !== part) element.style.display = 'none';
        }
      }
      stage.appendChild(sushi);
    })()`)
    return capture(win)
  }

  const images = {}
  const drawnLayers = {}
  for (const part of ['body', ...Object.keys(sushi.layers ?? {})]) {
    const image = await draw(part === 'body' ? 'body' : `layer-${part}`)
    const file = part === 'body' ? `sushi-${sushi.id}.png` : `sushi-${sushi.id}-${part}.png`
    fs.writeFileSync(path.join(resources, file), image.toPNG())
    console.log('wrote', `Resources/${file}`)
    images[part] = file
    drawnLayers[part] = image
  }

  // A point is where the drawn part starts (its topmost opaque pixels) or its middle, measured on
  // what was drawn, so a photo's transparent margins don't count.
  const points = {}
  for (const [name, point] of Object.entries(sushi.points ?? {})) {
    const image = point.layer ? drawnLayers[point.layer] : await draw(`point-${name}`)
    points[name] = pointOf(image, point.edge)
  }

  return { name: sushi.name, images, points, extent }
}

function pointOf(image, edge) {
  const { width, height } = image.getSize()
  const pixels = image.toBitmap()
  const opaque = (x, y) => pixels[(y * width + x) * 4 + 3] > 128
  const rows = []
  for (let y = 0; y < height; y++) {
    const xs = []
    for (let x = 0; x < width; x++) if (opaque(x, y)) xs.push(x)
    if (xs.length) rows.push({ y, xs })
  }
  if (!rows.length) throw new Error('nothing drawn to measure a point on')
  const unit = pixel => round(STAGE.min + (pixel / width) * STAGE.size)
  if (edge === 'top') {
    // The top few pixel rows, so a single stray pixel doesn't decide it.
    const band = rows.filter(row => row.y < rows[0].y + 6)
    const xs = band.flatMap(row => row.xs)
    return { x: unit(xs.reduce((a, b) => a + b, 0) / xs.length), y: unit(rows[0].y) }
  }
  const xs = rows.flatMap(row => row.xs)
  return { x: unit(xs.reduce((a, b) => a + b, 0) / xs.length), y: unit((rows[0].y + rows[rows.length - 1].y) / 2) }
}

async function capture(win) {
  await win.webContents.executeJavaScript('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))')
  win.webContents.invalidate()
  await win.webContents.capturePage() // the first capture after a change can be stale
  await win.webContents.executeJavaScript('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))')
  return win.webContents.capturePage({ x: 0, y: 0, width: PIXELS, height: PIXELS })
}

const round = value => Math.round(value * 100) / 100

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: PIXELS,
    height: PIXELS,
    show: false,
    transparent: true,
    frame: false,
    backgroundColor: '#00000000',
    enableLargerThanScreen: true,
    webPreferences: { offscreen: true },
  })
  await win.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(page))

  const classicText = fs.readFileSync(path.join(art, 'sushi.svg'), 'utf8')
  const classicSalmon = await win.webContents.executeJavaScript(`(() => {
    const inPage = ${inPage.toString()};
    return inPage(${JSON.stringify(classicText)}).salmon;
  })()`)

  // The classic sushi keeps its two images (body.png and propeller.png, its own 60×60 frame); its top
  // is the propeller's, which the speech bubble is placed to clear.
  const manifest = {
    stage: STAGE,
    sushis: [{ id: 'classic', name: 'Classic Sushi', images: { body: 'body.png', propeller: 'propeller.png' }, points: {}, extent: { top: 4, left: 10, right: 51, bottom: 55 } }],
  }
  for (const sushi of sushis.filter(one => one.file)) {
    manifest.sushis.push({ id: sushi.id, ...(await render(win, sushi, classicSalmon)) })
  }
  fs.writeFileSync(path.join(resources, 'sushis.json'), JSON.stringify(manifest, null, 2) + '\n')
  console.log('wrote Resources/sushis.json')
  app.quit()
}).catch(error => {
  console.error(error)
  app.exit(1)
})
