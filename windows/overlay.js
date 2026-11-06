// Draws one flight. `flight` comes from main.js; `at` freezes the clock at that second
// and `pets` lists pets (seconds into the flight), both for --preview.
const params = new URLSearchParams(location.search)
const flight = JSON.parse(params.get('flight') ?? '{}')
const frozenAt = params.has('at') ? Number(params.get('at')) : null
const petting = params.get('petting') === '1'
const sound = params.get('sound') ?? 'off'
const pets = (params.get('pets') ?? '').split(',').filter(Boolean).map(Number)

const sushi = document.getElementById('sushi')
const blades = document.getElementById('blades')
const hearts = document.getElementById('hearts')
const bubble = document.getElementById('bubble')
const size = SushiFlight.SIZE
const TURNS_PER_SECOND = 4.5
bubble.textContent = flight.message

/** What a pet does: two quick extra turns of the propeller, a squish, and hearts floating up. Same as FlightView.swift. */
function reaction(time) {
  let extraSpin = 0
  let squish = 1
  const floating = []
  for (const pet of pets) {
    if (time < pet) continue
    const age = time - pet
    const spin = Math.min(age / 0.9, 1)
    extraSpin += 720 * (1 - Math.pow(1 - spin, 3))
    if (age < 0.4) squish = 1 + 0.18 * Math.sin((Math.PI * age) / 0.4)
    if (age < 1.2) for (const dx of [-40, 0, 40]) floating.push({ dx, progress: age / 1.2 })
  }
  return { extraSpin, squish, floating }
}

function draw(time) {
  const pose = SushiFlight.pose(flight, time)
  const { extraSpin, squish, floating } = reaction(time)
  sushi.style.transform =
    `translate(${pose.x - size / 2}px, ${pose.y - size / 2}px) rotate(${pose.tilt}deg) scale(${squish})`
  blades.style.transform = `perspective(540px) rotateY(${time * 360 * TURNS_PER_SECOND + extraSpin}deg)`
  bubble.style.opacity = String(pose.bubble)
  bubble.style.transform =
    `translate(${pose.x}px, ${pose.y - size * 0.7}px) translate(-50%, -50%) scale(${0.6 + 0.4 * pose.bubble})`

  while (hearts.children.length < floating.length) {
    const heart = document.createElement('div')
    heart.className = 'heart'
    heart.textContent = '❤'
    hearts.append(heart)
  }
  Array.from(hearts.children).forEach((heart, index) => {
    const one = floating[index]
    heart.style.display = one ? 'block' : 'none'
    if (!one) return
    const x = pose.x + one.dx
    const y = pose.y - size * 0.3 - 90 * one.progress
    heart.style.opacity = String(1 - one.progress)
    heart.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) scale(${0.6 + 0.6 * one.progress})`
  })
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
      if (over) pets.push(now())
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
