// One trip across the screen: fly in, hover while saying something nice, fly out.
// The same motion as mac/Sources/SushiBuddy/Flight.swift, so both apps move alike.
// Loaded by main.js (require) and by overlay.html and tour.html (<script>, after looks.js).
;(function (root) {
  const looks = typeof module === 'object' && module.exports ? require('./looks') : root.SushiLooks
  const SIZE = 180
  const FLY_IN = 2.0
  const HOVER = 3.2
  const FLY_OUT = 2.0
  const DURATION = FLY_IN + HOVER + FLY_OUT
  const PATHS = ['classic', 'loop', 'bounce', 'zigzag']

  function between(low, high) {
    return low + Math.random() * (high - low)
  }

  /** `path` is one of PATHS, or 'random' for any of them. `look` is which sushi flies (looks.js). */
  function randomFlight(canvas, message, path = 'random', look = looks.CLASSIC) {
    return {
      width: canvas.width,
      height: canvas.height,
      message,
      path: PATHS.includes(path) ? path : PATHS[Math.floor(Math.random() * PATHS.length)],
      isLeftToRight: Math.random() < 0.5,
      hoverX: canvas.width * between(0.35, 0.65),
      altitude: canvas.height * between(0.3, 0.6),
      look,
    }
  }

  function previewFlight(canvas, path = 'classic', look = looks.CLASSIC) {
    return {
      width: canvas.width,
      height: canvas.height,
      message: "You're on a roll! 🍣",
      path,
      isLeftToRight: true,
      hoverX: canvas.width / 2,
      altitude: canvas.height * 0.62,
      look,
    }
  }

  const lookOf = flight => flight.look ?? looks.CLASSIC

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

  /** How long a flight hovers: HOVER, or as long as the tour holds it (`hover: Infinity`). */
  const hoverOf = flight => flight.hover ?? HOVER

  /** Ends the hover at `time`: the bubble fades, then the sushi flies off from where it is. */
  function letGo(flight, time) {
    return { ...flight, hover: Math.max(time - FLY_IN, 0) + 0.35 }
  }

  function bubbleVisibility(flight, time) {
    const appear = FLY_IN - 0.3
    const vanish = FLY_IN + hoverOf(flight)
    if (time < appear || time > vanish) return 0
    return Math.min((time - appear) / 0.35, (vanish - time) / 0.35, 1)
  }

  /**
   * Where the sushi is at `time`. The seasonal ones move their own way: Rainy Day floats slowly,
   * swaying under its umbrella; the Easter Bunny hops instead of following the path; Metalhead
   * headbangs while it hovers; Santa's pompom swings behind it.
   */
  function pose(flight, time) {
    const look = lookOf(flight).id
    const direction = flight.isLeftToRight ? 1 : -1
    const startX = flight.isLeftToRight ? -SIZE : flight.width + SIZE
    const endX = flight.isLeftToRight ? flight.width + SIZE : -SIZE
    let bob = Math.sin(time * 2 * Math.PI * 0.9) * 14
    let wobble = Math.sin(time * 2 * Math.PI * 0.6) * 3
    if (look === 'rainy') {
      bob = Math.sin(time * 2 * Math.PI * 0.5) * 18
      wobble = Math.sin(time * 2 * Math.PI * 0.5 + Math.PI / 2) * 7
    }
    const hover = hoverOf(flight)

    let x
    let lean
    let offset = { dx: 0, dy: 0, spin: 0 }
    if (time < FLY_IN) {
      const u = time / FLY_IN
      x = startX + (flight.hoverX - startX) * easeOut(u)
      lean = 12 * (1 - u)
      offset = look === 'bunny' ? hop(u, true) : pathOffset(flight.path, true, u, direction)
    } else if (time < FLY_IN + hover) {
      x = flight.hoverX + Math.sin((time - FLY_IN) * 2 * Math.PI * 0.35) * 8
      lean = 0
      if (look === 'bunny') offset.dy = -Math.max(0, Math.sin((time - FLY_IN) * 2 * Math.PI * 1.1)) * 16 * settle(flight, time)
    } else {
      // Leaves from where the hover's sway ended, so nothing jumps.
      const leaveX = flight.hoverX + Math.sin(hover * 2 * Math.PI * 0.35) * 8
      const u = Math.min((time - FLY_IN - hover) / FLY_OUT, 1)
      x = leaveX + (endX - leaveX) * easeIn(u)
      lean = 12 * u
      offset = look === 'bunny' ? hop(u, false) : pathOffset(flight.path, false, u, direction)
    }
    if (look === 'bunny') bob = 0

    const result = {
      x: x + offset.dx,
      y: flight.altitude + bob + offset.dy,
      tilt: direction * lean + wobble + offset.spin,
      bubble: bubbleVisibility(flight, time),
      pompom: 0,
    }
    if (look === 'metalhead') {
      // Nods from the bottom of the rice, so the head does the moving.
      const angle = headbang(flight, time)
      const pivot = SIZE * 0.38
      result.x += pivot * Math.sin((angle * Math.PI) / 180)
      result.y += pivot * (1 - Math.cos((angle * Math.PI) / 180))
      result.tilt += angle
    }
    if (look === 'santa') result.pompom = Math.sin(time * 2 * Math.PI * 1.3) * 18 - direction * lean * 1.2
    return result
  }

  /** The Easter Bunny's hops across the screen, highest far out and settling as it arrives. */
  function hop(u, isFlyIn) {
    return { dx: 0, dy: -Math.abs(Math.sin(u * Math.PI * 4)) * 55 * (isFlyIn ? 1 - u : u), spin: 0 }
  }

  /** Metalhead's nod in degrees: only while it hovers, easing in and out so nothing jumps. */
  function headbang(flight, time) {
    return Math.sin((time - FLY_IN) * 2 * Math.PI * 2.2) * 14 * settle(flight, time)
  }

  /**
   * 0 outside the hover, rising to 1 in its first 0.4 s and back to 0 in its last: how much of a
   * move made while hovering shows, so it starts and stops where the hover does.
   */
  function settle(flight, time) {
    const into = time - FLY_IN
    const hover = hoverOf(flight)
    if (!(into > 0 && into < hover)) return 0
    return Math.min(1, into / 0.4, (hover - into) / 0.4)
  }

  /** A named point of the art (looks.js), where it is on the canvas at `pose`, tilt included. */
  function point(flight, name, at) {
    const offset = looks.offsetOf(lookOf(flight), name, SIZE)
    if (!offset) return null
    const angle = (at.tilt * Math.PI) / 180
    return {
      x: at.x + offset.x * Math.cos(angle) - offset.y * Math.sin(angle),
      y: at.y + offset.x * Math.sin(angle) + offset.y * Math.cos(angle),
    }
  }

  const effect = (glyph, x, y, size, more = {}) => ({ glyph, x, y, size, rotation: 0, opacity: 1, isInFront: true, isWord: false, ...more })

  /**
   * What goes with the sushi at `time`: Rainy Day's leaves blowing past, J-Day's snow and the foam
   * from its can as it arrives, Santa's trail of sparkles, the egg the Easter Bunny drops, and
   * Metalhead's trail of flames and its horns while it headbangs. The classic has none. Each is an
   * emoji, a word in a little white label (`isWord`), or a bubble of foam (glyph 'bubble'),
   * `isInFront` of the sushi or behind it. Same as Flight.effects in Flight.swift.
   */
  function effects(flight, time) {
    const at = pose(flight, time)
    const direction = flight.isLeftToRight ? 1 : -1
    const hover = hoverOf(flight)
    const moving = then => then >= 0 && (then < FLY_IN || then > FLY_IN + hover)
    const fraction = value => value - Math.floor(value)

    switch (lookOf(flight).id) {
      case 'rainy':
        return [0, 1, 2].map(leaf => {
          const q = fraction(time / 2.6 + leaf / 3)
          return effect(
            leaf === 1 ? '🍁' : '🍂',
            at.x + direction * SIZE * (0.9 - 1.8 * q),
            at.y - SIZE * 0.25 + SIZE * 0.55 * q + Math.sin(q * 2 * Math.PI * 1.5 + leaf) * SIZE * 0.06,
            30,
            { rotation: q * 480 * (leaf % 2 === 0 ? 1 : -1), opacity: Math.sin(q * Math.PI) },
          )
        })
      case 'jday': {
        const list = Array.from({ length: 10 }, (_, flake) => {
          const q = fraction(time / 3.2 + flake * 0.37)
          return effect(
            '❄️',
            at.x + (flake / 9 - 0.5) * SIZE * 1.8 + Math.sin(time * 1.3 + flake) * 10,
            at.y - SIZE * 0.85 + q * SIZE * 1.5,
            14 + (flake % 3) * 4,
            { rotation: time * 40 + flake * 30, opacity: Math.sin(q * Math.PI) * 0.95, isInFront: flake % 2 === 0 },
          )
        })
        const can = point(flight, 'can', at)
        if (can) {
          const opened = FLY_IN - 0.1
          for (let bubble = 0; bubble < 7; bubble++) {
            const age = time - opened - bubble * 0.12
            if (!(age > 0 && age < 1.1)) continue
            const q = age / 1.1
            list.push(
              effect('bubble', can.x + Math.sin(age * 9 + bubble) * 6 + ((bubble % 3) - 1) * 6, can.y - q * SIZE * 0.35, 8 + (bubble % 3) * 3, {
                opacity: 1 - q,
              }),
            )
          }
          const age = time - opened
          if (age > 0 && age < 1.0) {
            list.push(effect('pssht!', can.x + 30, can.y - SIZE * 0.3, 18, { rotation: -8, opacity: 1 - age, isWord: true }))
          }
        }
        return list
      }
      case 'santa':
        return [1, 2, 3, 4, 5, 6].flatMap(spark => {
          const then = time - spark * 0.08
          if (!moving(then)) return []
          const trail = pose(flight, then)
          return [effect('✨', trail.x, trail.y + SIZE * 0.1, 32 - spark * 2, { rotation: spark * 25, opacity: 1 - spark / 8, isInFront: false })]
        })
      case 'bunny': {
        const dropped = FLY_IN + 0.8
        const age = time - dropped
        const basket = age >= 0 && age < 1.6 ? point(flight, 'basket', pose(flight, dropped)) : null
        if (!basket) return []
        const gravity = SIZE * 6
        const fall = SIZE * 0.55
        const landed = Math.sqrt((2 * fall) / gravity)
        let drop = age < landed ? 0.5 * gravity * age * age : fall
        if (age >= landed) {
          const since = age - landed
          drop -= Math.max(0, 0.35 * Math.sqrt(2 * gravity * fall) * since - 0.5 * gravity * since * since)
        }
        return [
          effect('🥚', basket.x + age * direction * SIZE * 0.15, basket.y + drop, 26, {
            rotation: Math.min(age, landed) * 200,
            opacity: age > 1.2 ? 1 - (age - 1.2) / 0.4 : 1,
          }),
        ]
      }
      case 'metalhead': {
        const list = [1, 2, 3, 4, 5].flatMap(flame => {
          const then = time - flame * 0.07
          if (!moving(then)) return []
          const trail = pose(flight, then)
          return [effect('🔥', trail.x - direction * SIZE * 0.15, trail.y + SIZE * 0.15, 34 - flame * 2, { opacity: 1 - flame / 7, isInFront: false })]
        })
        const nod = Math.abs(headbang(flight, time)) / 14
        if (nod > 0) {
          list.push(
            effect('🤘', at.x - direction * SIZE * 0.55, at.y - SIZE * 0.1 - nod * 8, 30, {
              opacity: settle(flight, time),
            }),
          )
        }
        return list
      }
      default:
        return []
    }
  }

  /**
   * What a pet does: two quick extra turns of the propeller, a squish, and hearts floating up.
   * `pets` are seconds into the flight. Same as PetReaction in FlightView.swift.
   */
  function petReaction(pets, time) {
    let extraSpin = 0
    let squish = 1
    const hearts = []
    for (const pet of pets) {
      if (time < pet) continue
      const age = time - pet
      const spin = Math.min(age / 0.9, 1)
      extraSpin += 720 * (1 - Math.pow(1 - spin, 3))
      if (age < 0.4) squish = 1 + 0.18 * Math.sin((Math.PI * age) / 0.4)
      if (age < 1.2) for (const dx of [-40, 0, 40]) hearts.push({ dx, progress: age / 1.2 })
    }
    return { extraSpin, squish, hearts }
  }

  const api = { SIZE, FLY_IN, HOVER, FLY_OUT, DURATION, PATHS, randomFlight, previewFlight, pathOffset, pose, effects, point, letGo, petReaction }
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.SushiFlight = api
})(this)
