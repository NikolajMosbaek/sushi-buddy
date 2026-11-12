// Draws one flight. `flight` comes from main.js; `at` freezes the clock at that second
// and `pets` lists pets (seconds into the flight), both for --preview.
const params = new URLSearchParams(location.search)
const flight = JSON.parse(params.get('flight') ?? '{}')
const frozenAt = params.has('at') ? Number(params.get('at')) : null
const petting = params.get('petting') === '1'
const sound = params.get('sound') ?? 'off'
const pets = (params.get('pets') ?? '').split(',').filter(Boolean).map(Number)

const bubble = document.getElementById('bubble')
const drawSushi = SushiView.create(document, flight.look, flight.stage)
const size = SushiFlight.SIZE
const lift = SushiLooks.bubbleLift(flight.look ?? SushiLooks.CLASSIC, size)
bubble.textContent = flight.message

function draw(time) {
  const pose = SushiFlight.pose(flight, time)
  drawSushi(pose, time, pets, SushiFlight.effects(flight, time))
  bubble.style.opacity = String(pose.bubble)
  bubble.style.transform =
    `translate(${pose.x}px, ${pose.y - size * 0.7 - lift}px) translate(-50%, -50%) scale(${0.6 + 0.4 * pose.bubble})`
  return pose
}

function play(name, delay) {
  setTimeout(() => {
    const audio = new Audio(`assets/${name}.wav`)
    audio.volume = 0.5
    audio.play().catch(() => {})
  }, delay * 1000)
}

window.addEventListener('load', () => {
  if (frozenAt !== null) {
    draw(frozenAt)
    return
  }
  if (sound === 'chime') play('chime', SushiFlight.FLY_IN - 0.3)
  if (sound === 'whirr') play('whirr', 0)

  // Petting: the app lets clicks through except while the mouse is over the sushi.
  let mouse = null
  let over = false
  let pose = null
  const start = performance.now()
  const now = () => (performance.now() - start) / 1000
  if (petting) {
    window.addEventListener('mousemove', event => {
      mouse = { x: event.clientX, y: event.clientY }
    })
    window.addEventListener('mousedown', () => {
      if (!over) return
      pets.push(now())
      window.sushiOverlay?.petted()
    })
  }

  const frame = () => {
    const time = now()
    pose = draw(time)
    if (petting) {
      const isOver = mouse !== null && Math.hypot(mouse.x - pose.x, mouse.y - pose.y) < size * 0.42
      if (isOver !== over) {
        over = isOver
        window.sushiOverlay?.setOverSushi(over)
      }
    }
    if (time < SushiFlight.DURATION) requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
})
