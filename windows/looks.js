// The sushis there are (Resources/sushis.json, which Art/render-sushis.js writes), and which one
// flies: the one chosen in Settings, or by the calendar. Same rules as mac/Sources/SushiBuddy/Looks.swift.
// Loaded by main.js (require) and by overlay.html and tour.html (<script>).
;(function (root) {
  const BY_THE_CALENDAR = 'calendar'

  const STAGE = { min: -20, size: 100 }

  const CLASSIC = {
    id: 'classic',
    name: 'Classic Sushi',
    images: { body: 'body.png', propeller: 'propeller.png' },
    points: {},
    top: 4,
  }

  /**
   * The manifest's sushis as looks (id, name, images, points in classic units, and how high they
   * reach), classic first, and the stage a seasonal sushi's images cover, in classic units.
   */
  function decode(manifest) {
    const sushis = Array.isArray(manifest?.sushis) ? manifest.sushis : []
    const looks = sushis.map(entry => ({
      id: entry.id,
      name: entry.name,
      images: entry.images ?? {},
      points: entry.points ?? {},
      top: entry.extent?.top ?? CLASSIC.top,
    }))
    return { stage: manifest?.stage ?? STAGE, looks: looks.length ? looks : [CLASSIC] }
  }

  function named(looks, id) {
    return looks.find(look => look.id === id) ?? looks[0] ?? CLASSIC
  }

  function resolve(choice, year, month, day) {
    return choice === BY_THE_CALENDAR ? seasonal(year, month, day) : choice
  }

  /** The sushi to fly on `date` (local time), for the choice in Settings. */
  function current(looks, choice, date = new Date()) {
    return named(looks, resolve(choice, date.getFullYear(), date.getMonth() + 1, date.getDate()))
  }

  /**
   * Which sushi the calendar picks on a day: Rainy Day all September, J-Day from J-dag (the first
   * Friday of November) to the end of November, Santa 1–26 December, the Easter Bunny from Palm
   * Sunday to Easter Monday, Metalhead all June (Copenhell), and the classic the rest of the year.
   */
  function seasonal(year, month, day) {
    switch (month) {
      case 6:
        return 'metalhead'
      case 9:
        return 'rainy'
      case 11:
        return day >= firstFridayOfNovember(year) ? 'jday' : 'classic'
      case 12:
        return day <= 26 ? 'santa' : 'classic'
      default: {
        const today = dayOfYear(year, month, day)
        const easter = easterSunday(year)
        const easterDay = dayOfYear(year, easter.month, easter.day)
        return today >= easterDay - 7 && today <= easterDay + 1 ? 'bunny' : 'classic'
      }
    }
  }

  /** Easter Sunday in the Gregorian calendar (the Meeus/Jones/Butcher algorithm). */
  function easterSunday(year) {
    const div = (a, b) => Math.floor(a / b)
    const a = year % 19
    const b = div(year, 100)
    const c = year % 100
    const d = div(b, 4)
    const e = b % 4
    const f = div(b + 8, 25)
    const g = div(b - f + 1, 3)
    const h = (19 * a + b - d - g + 15) % 30
    const i = div(c, 4)
    const k = c % 4
    const l = (32 + 2 * e + 2 * i - h - k) % 7
    const m = div(a + 11 * h + 22 * l, 451)
    return { month: div(h + l - 7 * m + 114, 31), day: ((h + l - 7 * m + 114) % 31) + 1 }
  }

  /** The day of November that is its first Friday. */
  function firstFridayOfNovember(year) {
    const friday = 5 // counting from Sunday = 0
    return 1 + ((friday - weekday(year, 11, 1) + 7) % 7)
  }

  /** Sunday = 0 … Saturday = 6 (Sakamoto's method), so no time zone gets a say. */
  function weekday(year, month, day) {
    const offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    const y = month < 3 ? year - 1 : year
    const div = (a, b) => Math.floor(a / b)
    return (y + div(y, 4) - div(y, 100) + div(y, 400) + offsets[month - 1] + day) % 7
  }

  function dayOfYear(year, month, day) {
    const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
    const lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return lengths.slice(0, month - 1).reduce((sum, length) => sum + length, 0) + day
  }

  /** How far a point is from the sushi's centre in a flight `size` wide, before any tilt. */
  function offsetOf(look, point, size) {
    const at = look.points?.[point]
    return at ? { x: ((at.x - 30) * size) / 60, y: ((at.y - 30) * size) / 60 } : null
  }

  /** What floats up when it's petted, in place of the hearts (null: hearts). */
  function petGlyph(look) {
    return look.id === 'metalhead' ? '🤘' : null
  }

  /** How much higher the speech bubble sits than over the classic sushi, to clear ears and hats. */
  function bubbleLift(look, size) {
    return (Math.max(0, CLASSIC.top - (look.top ?? CLASSIC.top)) * size) / 60
  }

  const api = { BY_THE_CALENDAR, CLASSIC, STAGE, decode, named, resolve, current, seasonal, easterSunday, firstFridayOfNovember, weekday, offsetOf, petGlyph, bubbleLift }
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.SushiLooks = api
})(this)
