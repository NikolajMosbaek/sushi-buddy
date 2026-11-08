// Draws the tour. main.js passes where the sushi waits (`spot`), the screen's size (`canvas`)
// and the shortcut's label, or other `steps` and a `close` label (What's New); --preview-tour
// adds `step` and `at` to draw one moment of one step.
const params = new URLSearchParams(location.search)
const spot = JSON.parse(params.get('spot'))
const canvas = JSON.parse(params.get('canvas'))
const frozenAt = params.has('at') ? Number(params.get('at')) : null
const app = window.sushiTourApp
const steps = params.has('steps') ? JSON.parse(params.get('steps')) : SushiTour.steps('windows', params.get('shortcut') || null)

// In from the far side, so the sushi crosses the screen to its icon, and out the near side.
let flight = {
  width: canvas.width,
  height: canvas.height,
  message: '',
  path: 'classic',
  isLeftToRight: spot.bubbleOnLeft,
  hoverX: spot.x,
  altitude: spot.y,
  hover: Infinity,
}
let index = Number(params.get('step') ?? 0)
let leaving = false
let settings = null
const pets = []
const loops = []
const copied = new Set()
const start = performance.now()
const now = () => frozenAt ?? (performance.now() - start) / 1000

const byId = id => document.getElementById(id)
const bubble = byId('bubble')
const drawSushi = SushiView.create(document)

// The bubble's corner nearest the sushi, and its tail on that side.
const corner = SushiTour.bubbleCorner(spot)
if (spot.bubbleOnLeft) bubble.style.right = `${canvas.width - corner.x}px`
else bubble.style.left = `${corner.x}px`
if (spot.bubbleBelow) bubble.style.top = `${corner.y}px`
else bubble.style.bottom = `${canvas.height - corner.y}px`
bubble.classList.add(spot.bubbleOnLeft ? 'tail-right' : 'tail-left', spot.bubbleBelow ? 'tail-top' : 'tail-bottom')

function play(name) {
  const audio = new Audio(`assets/${name}.wav`)
  audio.volume = 0.5
  audio.play().catch(() => {})
}

function render() {
  const step = steps[index]
  const isLast = index === steps.length - 1
  byId('text').textContent = step.text

  const switches = byId('switches')
  switches.replaceChildren(
    ...step.switches.map(toggle => {
      const label = document.createElement('label')
      const box = document.createElement('input')
      box.type = 'checkbox'
      box.checked = settings != null && SushiTour.isOn(toggle, settings)
      box.addEventListener('change', async () => {
        settings = await app.set(toggle.key, SushiTour.valueFor(toggle, settings, box.checked))
        if (box.checked && toggle.plays) play(toggle.plays)
        render()
      })
      label.append(box, toggle.label)
      return label
    }),
  )

  const copy = byId('copy')
  copy.hidden = !step.copies
  copy.textContent = copied.has(step.id) ? 'Copied! Paste it in a terminal.' : 'Copy the install command'
  byId('link').hidden = !step.link
  byId('skip').textContent = params.get('close') || 'Skip tour'
  byId('skip').hidden = isLast
  byId('back').hidden = index === 0
  byId('count').textContent = `${index + 1} of ${steps.length}`
  byId('next').textContent = isLast ? 'Done' : 'Next'
}

function finish() {
  if (leaving) return
  leaving = true
  flight = SushiFlight.letGo(flight, now())
  setTimeout(() => app.done(), (0.35 + SushiFlight.FLY_OUT + 0.3) * 1000)
}

// Coming to the tricks step, from either side, shows a loop-the-loop.
function go(by) {
  index += by
  if (steps[index].showsLoop) loops.push(now() + 0.2)
  render()
}

byId('next').addEventListener('click', () => {
  if (leaving) return
  if (index === steps.length - 1) return finish()
  go(1)
})
byId('back').addEventListener('click', () => {
  if (leaving || index === 0) return
  go(-1)
})
byId('skip').addEventListener('click', finish)
byId('link').addEventListener('click', () => app.openReleaseNotes())
byId('copy').addEventListener('click', async () => {
  await app.copyInstall()
  copied.add(steps[index].id)
  render()
})

function draw(time) {
  const pose = SushiTour.tourPose(flight, time, loops)
  drawSushi(pose, time, pets)
  bubble.style.opacity = String(pose.bubble)
  bubble.style.pointerEvents = pose.bubble > 0.5 ? 'auto' : 'none'
  return pose
}

window.addEventListener('load', async () => {
  settings = await app.settings()
  render()
  if (frozenAt !== null) {
    draw(frozenAt)
    return
  }

  // The app lets clicks through except while the mouse is over the sushi or the bubble.
  let mouse = null
  let over = false
  let pose = null
  window.addEventListener('mousemove', event => {
    mouse = { x: event.clientX, y: event.clientY }
  })
  window.addEventListener('mousedown', () => {
    if (pose && mouse && Math.hypot(mouse.x - pose.x, mouse.y - pose.y) < SushiTour.SUSHI_SIZE * 0.42) pets.push(now())
  })
  app.onReact(() => pets.push(now()))

  const frame = () => {
    const time = now()
    pose = draw(time)
    const rect = bubble.getBoundingClientRect()
    const shown = pose.bubble > 0.5 ? { x: rect.left, y: rect.top, width: rect.width, height: rect.height } : null
    const isOver = mouse !== null && SushiTour.isOver(mouse, pose, shown)
    if (isOver !== over) {
      over = isOver
      app.setOverSushi(over)
    }
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
})
