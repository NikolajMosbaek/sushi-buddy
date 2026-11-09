// The same cases as mac/Tests/SushiBuddyTests/LooksTests.swift, so both apps fly the same sushi on the same day.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { test } = require('node:test')

const looks = require('../looks')
const { CHOICES, DEFAULTS, normalize } = require('../settings')

const on = (year, month, day) => looks.seasonal(year, month, day)

test('Easter Sunday follows the church calendar', () => {
  const known = [[2008, 3, 23], [2024, 3, 31], [2025, 4, 20], [2026, 4, 5], [2027, 3, 28], [2038, 4, 25], [2285, 3, 22]]
  for (const [year, month, day] of known) assert.deepEqual(looks.easterSunday(year), { month, day }, `Easter ${year}`)
})

test('J-dag is the first Friday of November', () => {
  assert.equal(looks.firstFridayOfNovember(2024), 1)
  assert.equal(looks.firstFridayOfNovember(2025), 7)
  assert.equal(looks.firstFridayOfNovember(2026), 6)
  assert.equal(looks.firstFridayOfNovember(2027), 5)
})

test("the calendar picks each season's sushi from its first day to its last", () => {
  assert.equal(on(2026, 8, 31), 'classic')
  assert.equal(on(2026, 9, 1), 'rainy')
  assert.equal(on(2026, 9, 30), 'rainy')
  assert.equal(on(2026, 10, 1), 'classic')
  assert.equal(on(2026, 11, 5), 'classic')
  assert.equal(on(2026, 11, 6), 'jday')
  assert.equal(on(2026, 11, 30), 'jday')
  assert.equal(on(2026, 12, 1), 'santa')
  assert.equal(on(2026, 12, 26), 'santa')
  assert.equal(on(2026, 12, 27), 'classic')
  assert.equal(on(2027, 1, 1), 'classic')
  assert.equal(on(2026, 5, 31), 'classic')
  assert.equal(on(2026, 6, 1), 'metalhead')
  assert.equal(on(2026, 6, 30), 'metalhead')
  assert.equal(on(2026, 7, 1), 'classic')
})

test('the Easter Bunny comes from Palm Sunday to Easter Monday', () => {
  assert.equal(on(2026, 3, 28), 'classic')
  assert.equal(on(2026, 3, 29), 'bunny')
  assert.equal(on(2026, 4, 6), 'bunny')
  assert.equal(on(2026, 4, 7), 'classic')
  // Across the turn of a month, and in a leap year.
  assert.equal(on(2027, 3, 20), 'classic')
  assert.equal(on(2027, 3, 21), 'bunny')
  assert.equal(on(2027, 3, 29), 'bunny')
  assert.equal(on(2027, 3, 30), 'classic')
  assert.equal(on(2024, 4, 1), 'bunny')
  assert.equal(on(2024, 4, 2), 'classic')
})

test('a sushi chosen in Settings flies all year', () => {
  assert.equal(looks.resolve('santa', 2026, 7, 1), 'santa')
  assert.equal(looks.resolve('classic', 2026, 12, 24), 'classic')
  assert.equal(looks.resolve(looks.BY_THE_CALENDAR, 2026, 12, 24), 'santa')
})

test('the sushi defaults to the calendar and refuses an unknown one', () => {
  assert.equal(DEFAULTS.sushi, looks.BY_THE_CALENDAR)
  assert.equal(normalize({ sushi: 'bunny' }).sushi, 'bunny')
  assert.equal(normalize({ sushi: 'tuna' }).sushi, looks.BY_THE_CALENDAR)
})

test('the bundled sushis are the choices in Settings, with their images', () => {
  const resources = path.join(__dirname, '..', '..', 'Resources')
  const bundled = looks.decode(JSON.parse(fs.readFileSync(path.join(resources, 'sushis.json'), 'utf8'))).looks
  assert.deepEqual(
    bundled.map(look => look.id),
    CHOICES.sushi.slice(1),
  )
  assert.deepEqual(bundled[0], looks.CLASSIC)
  for (const look of bundled) {
    assert.ok(look.name, `${look.id} has no name`)
    assert.ok(look.images.body, `${look.id} has no body`)
    for (const file of Object.values(look.images)) assert.ok(fs.existsSync(path.join(resources, file)), `${file} is missing`)
  }
  assert.deepEqual(
    bundled.filter(look => look.images.propeller).map(look => look.id),
    ['classic'],
  )
})

test("points are measured from the sushi's centre, and tall art lifts the bubble", () => {
  const look = { id: 'test', name: 'Test', images: {}, points: { can: { x: 45, y: 15 } }, top: -5 }
  assert.deepEqual(looks.offsetOf(look, 'can', 180), { x: 45, y: -45 })
  assert.equal(looks.offsetOf(look, 'basket', 180), null)
  assert.equal(looks.bubbleLift(look, 180), 27)
  assert.equal(looks.bubbleLift(looks.CLASSIC, 180), 0)
  assert.equal(looks.bubbleLift({ ...look, top: 9 }, 180), 0)
})

// How each sushi moves: the same cases as LooksTests.swift.
const { FLY_IN, HOVER, effects, pose, previewFlight } = require('../flight')
const bundledLooks = looks.decode(JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'Resources', 'sushis.json'), 'utf8'))).looks
const flightAs = (id, overrides = {}) => ({ ...previewFlight({ width: 1600, height: 900 }, 'classic', looks.named(bundledLooks, id)), ...overrides })
const times = Array.from({ length: 72 }, (_, i) => i / 10)

test('no sushi jumps where the fly-in meets the hover or the hover meets the fly-out, held or not', () => {
  for (const look of bundledLooks) {
    for (const hover of [HOVER, 1.25]) {
      const flight = flightAs(look.id, { hover })
      for (const edge of [FLY_IN, FLY_IN + hover]) {
        const before = pose(flight, edge - 1e-6)
        const after = pose(flight, edge + 1e-6)
        assert.ok(Math.hypot(before.x - after.x, before.y - after.y) < 0.01, `${look.id} at ${edge}s`)
        assert.ok(Math.abs(before.tilt - after.tilt) < 0.01, `${look.id} tilt at ${edge}s`)
      }
    }
  }
})

test('the Easter Bunny hops up from the line, never below it', () => {
  const flight = flightAs('bunny')
  assert.ok(times.every(time => pose(flight, time).y <= flight.altitude + 1e-9))
  assert.ok(times.some(time => pose(flight, time).y < flight.altitude - 20))
})

test('Metalhead headbangs only while it hovers', () => {
  const metal = flightAs('metalhead')
  const classic = flightAs('classic')
  for (const time of times.filter(time => time < FLY_IN || time > FLY_IN + HOVER)) {
    assert.ok(Math.abs(pose(metal, time).tilt - pose(classic, time).tilt) < 1e-9, `at ${time}s`)
  }
  assert.ok(times.some(time => Math.abs(pose(metal, time).tilt - pose(classic, time).tilt) > 8))
})

test('each sushi brings its own effects, at their moments; the classic brings none', () => {
  const at = (id, time) => effects(flightAs(id), time)
  assert.ok(times.every(time => at('classic', time).length === 0))
  // Santa's sparkles trail it only while it moves.
  assert.ok(at('santa', 1.0).length > 0)
  assert.equal(at('santa', FLY_IN + 1.5).length, 0)
  // The bunny drops its egg once it hovers, and the egg falls.
  assert.equal(at('bunny', FLY_IN + 0.7).length, 0)
  const falling = [0.9, 1.0, 1.1].map(after => at('bunny', FLY_IN + after)[0].y)
  assert.ok(falling[0] < falling[1] && falling[1] < falling[2])
  // J-Day's can foams as it arrives, then stops.
  assert.ok(at('jday', FLY_IN + 0.2).some(effect => effect.glyph === 'bubble'))
  assert.ok(!at('jday', FLY_IN + 2).some(effect => effect.glyph === 'bubble' || effect.isWord))
  // Rainy Day's leaves blow by the whole way.
  assert.ok(times.every(time => at('rainy', time).length === 3))
  for (const look of bundledLooks) {
    for (const time of times) {
      for (const one of at(look.id, time)) assert.ok(one.opacity >= 0 && one.opacity <= 1, `${look.id} ${one.glyph} at ${time}s`)
    }
  }
})
