// One trip across the screen: fly in, hover while saying something nice, fly out.
// The same motion as mac/Sources/SushiBuddy/Flight.swift, so both apps move alike.
// Loaded by main.js (require) and by overlay.html (<script>).
;(function (root) {
  const SIZE = 180
  const FLY_IN = 2.0
  const HOVER = 3.2
  const FLY_OUT = 2.0
  const DURATION = FLY_IN + HOVER + FLY_OUT

  function between(low, high) {
    return low + Math.random() * (high - low)
  }

  function randomFlight(canvas, lines) {
    return {
      width: canvas.width,
      height: canvas.height,
      message: lines[Math.floor(Math.random() * lines.length)] ?? "You've got this!",
      isLeftToRight: Math.random() < 0.5,
      hoverX: canvas.width * between(0.35, 0.65),
      altitude: canvas.height * between(0.3, 0.6),
    }
  }

  function previewFlight(canvas) {
    return {
      width: canvas.width,
      height: canvas.height,
      message: "You're on a roll! 🍣",
      isLeftToRight: true,
      hoverX: canvas.width / 2,
      altitude: canvas.height * 0.62,
    }
  }

  const easeOut = u => 1 - Math.pow(1 - u, 3)
  const easeIn = u => u * u * u

  function bubbleVisibility(time) {
    const appear = FLY_IN - 0.3
    const vanish = FLY_IN + HOVER
    if (time < appear || time > vanish) return 0
    return Math.min((time - appear) / 0.35, (vanish - time) / 0.35, 1)
  }

  function pose(flight, time) {
    const direction = flight.isLeftToRight ? 1 : -1
    const startX = flight.isLeftToRight ? -SIZE : flight.width + SIZE
    const endX = flight.isLeftToRight ? flight.width + SIZE : -SIZE
    const bob = Math.sin(time * 2 * Math.PI * 0.9) * 14
    const wobble = Math.sin(time * 2 * Math.PI * 0.6) * 3

    let x
    let lean
    if (time < FLY_IN) {
      const u = time / FLY_IN
      x = startX + (flight.hoverX - startX) * easeOut(u)
      lean = 12 * (1 - u)
    } else if (time < FLY_IN + HOVER) {
      x = flight.hoverX + Math.sin((time - FLY_IN) * 2 * Math.PI * 0.35) * 8
      lean = 0
    } else {
      const u = Math.min((time - FLY_IN - HOVER) / FLY_OUT, 1)
      x = flight.hoverX + (endX - flight.hoverX) * easeIn(u)
      lean = 12 * u
    }

    return { x, y: flight.altitude + bob, tilt: direction * lean + wobble, bubble: bubbleVisibility(time) }
  }

  const api = { SIZE, FLY_IN, HOVER, FLY_OUT, DURATION, randomFlight, previewFlight, pose }
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.SushiFlight = api
})(this)
