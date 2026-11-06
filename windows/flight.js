// One trip across the screen: fly in, hover while saying something nice, fly out.
// The same motion as mac/Sources/SushiBuddy/Flight.swift, so both apps move alike.
// Loaded by main.js (require) and by overlay.html (<script>).
;(function (root) {
  const SIZE = 180
  const FLY_IN = 2.0
  const HOVER = 3.2
  const FLY_OUT = 2.0
  const DURATION = FLY_IN + HOVER + FLY_OUT
  const PATHS = ['classic', 'loop', 'bounce', 'zigzag']

  function between(low, high) {
    return low + Math.random() * (high - low)
  }

  /** `path` is one of PATHS, or 'random' for any of them. */
  function randomFlight(canvas, message, path = 'random') {
    return {
      width: canvas.width,
      height: canvas.height,
      message,
      path: PATHS.includes(path) ? path : PATHS[Math.floor(Math.random() * PATHS.length)],
      isLeftToRight: Math.random() < 0.5,
      hoverX: canvas.width * between(0.35, 0.65),
      altitude: canvas.height * between(0.3, 0.6),
    }
  }

  function previewFlight(canvas, path = 'classic') {
    return {
      width: canvas.width,
      height: canvas.height,
      message: "You're on a roll! 🍣",
      path,
      isLeftToRight: true,
      hoverX: canvas.width / 2,
      altitude: canvas.height * 0.62,
    }
  }

  const easeOut = u => 1 - Math.pow(1 - u, 3)
  const easeIn = u => u * u * u
  const smoothstep = u => u * u * (3 - 2 * u)
  const clamp = u => Math.min(Math.max(u, 0), 1)

  /**
   * How far a path strays from the straight line at progress `u` (0…1) of the fly-in or the
   * fly-out: every path is back on the line at both ends, so the hover starts and ends in place.
   * `spin` is extra rotation in degrees.
   */
  function pathOffset(path, isFlyIn, u, direction) {
    switch (path) {
      case 'loop': {
        if (!isFlyIn) return { dx: 0, dy: 0, spin: 0 }
        const angle = 2 * Math.PI * smoothstep(clamp((u - 0.25) / 0.5))
        return { dx: direction * 70 * Math.sin(angle), dy: -70 * (1 - Math.cos(angle)), spin: (-direction * angle * 180) / Math.PI }
      }
      case 'bounce':
        return { dx: 0, dy: -Math.abs(Math.sin(u * Math.PI * 3)) * 80 * (isFlyIn ? 1 - u : u), spin: 0 }
      case 'zigzag':
        return { dx: 0, dy: Math.sin(u * Math.PI * 4) * 60 * (isFlyIn ? 1 - u : u), spin: 0 }
      default:
        return { dx: 0, dy: 0, spin: 0 }
    }
  }

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
    let offset = { dx: 0, dy: 0, spin: 0 }
    if (time < FLY_IN) {
      const u = time / FLY_IN
      x = startX + (flight.hoverX - startX) * easeOut(u)
      lean = 12 * (1 - u)
      offset = pathOffset(flight.path, true, u, direction)
    } else if (time < FLY_IN + HOVER) {
      x = flight.hoverX + Math.sin((time - FLY_IN) * 2 * Math.PI * 0.35) * 8
      lean = 0
    } else {
      // Leaves from where the hover's sway ended, so nothing jumps.
      const leaveX = flight.hoverX + Math.sin(HOVER * 2 * Math.PI * 0.35) * 8
      const u = Math.min((time - FLY_IN - HOVER) / FLY_OUT, 1)
      x = leaveX + (endX - leaveX) * easeIn(u)
      lean = 12 * u
      offset = pathOffset(flight.path, false, u, direction)
    }

    return {
      x: x + offset.dx,
      y: flight.altitude + bob + offset.dy,
      tilt: direction * lean + wobble + offset.spin,
      bubble: bubbleVisibility(time),
    }
  }

  const api = { SIZE, FLY_IN, HOVER, FLY_OUT, DURATION, PATHS, randomFlight, previewFlight, pathOffset, pose }
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.SushiFlight = api
})(this)
