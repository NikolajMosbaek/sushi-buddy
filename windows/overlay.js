// Draws one flight. `flight` comes from main.js; `at` freezes the clock at
// that second, for --preview.
const params = new URLSearchParams(location.search)
const flight = JSON.parse(params.get('flight') ?? '{}')
const frozenAt = params.has('at') ? Number(params.get('at')) : null

const sushi = document.getElementById('sushi')
const bubble = document.getElementById('bubble')
const size = SushiFlight.SIZE
bubble.textContent = flight.message

function draw(time) {
  const pose = SushiFlight.pose(flight, time)
  sushi.style.transform = `translate(${pose.x - size / 2}px, ${pose.y - size / 2}px) rotate(${pose.tilt}deg)`
  bubble.style.opacity = String(pose.bubble)
  bubble.style.transform =
    `translate(${pose.x}px, ${pose.y - size * 0.7}px) translate(-50%, -50%) scale(${0.6 + 0.4 * pose.bubble})`
}

window.addEventListener('load', () => {
  if (frozenAt !== null) {
    draw(frozenAt)
    return
  }
  const start = performance.now()
  const frame = now => {
    const time = (now - start) / 1000
    draw(time)
    if (time < SushiFlight.DURATION) requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
})
