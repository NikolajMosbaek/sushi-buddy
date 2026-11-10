// The website's sushi. The apps' own looks.js, flight.js and sushi-view.js fly it across the sky at
// the top, so it moves exactly as it does on a desktop: the sushi the calendar picks today, or the
// one clicked further down.
;(async function () {
  const sky = document.getElementById('sky')
  const stageNode = document.getElementById('stage')
  const sushiNode = document.getElementById('sushi')
  const bubble = document.getElementById('bubble')
  const caption = document.getElementById('caption')
  const size = SushiFlight.SIZE
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches

  const fetchJSON = path =>
    fetch(path)
      .then(response => (response.ok ? response.json() : null))
      .catch(() => null)
  const [manifest, lines] = await Promise.all([fetchJSON('assets/sushis.json'), fetchJSON('assets/lines.json')])
  const { stage, looks } = SushiLooks.decode(manifest)
  const today = SushiLooks.current(looks, SushiLooks.BY_THE_CALENDAR)
  const sayings = lines?.anytime?.length ? lines.anytime : ["You're on a roll! 🍣"]

  let look = today
  let flight = null
  let draw = null
  let started = 0
  let pets = []
  let pose = null
  let frame = 0
  let again = 0
  let scale = 1
  let inView = true
  let lastSaying = -1

  function saying() {
    let index = Math.floor(Math.random() * sayings.length)
    if (index === lastSaying) index = (index + 1) % sayings.length
    lastSaying = index
    return sayings[index]
  }

  function measure() {
    scale = Math.min(1, sky.clientWidth / 640)
    const width = sky.clientWidth / scale
    const height = sky.clientHeight / scale
    stageNode.style.width = `${width}px`
    stageNode.style.height = `${height}px`
    stageNode.style.transform = `scale(${scale})`
    return { width, height }
  }

  function describe() {
    caption.textContent =
      look.id === today.id
        ? `Today the calendar picks the ${look.name}. Click it as it flies by to pet it.`
        : `That's the ${look.name}. Click it as it flies by to pet it.`
  }

  function fly(next = look) {
    cancelAnimationFrame(frame)
    clearTimeout(again)
    waiting = false
    look = next
    sky.dataset.look = look.id
    describe()
    // sushi-view.js puts a seasonal sushi's images in #sushi; the classic one needs its own two back.
    sushiNode.innerHTML = '<img src="assets/body.png" alt="" /><img id="blades" src="assets/propeller.png" alt="" />'
    for (const id of ['hearts', 'effects-back', 'effects-front']) document.getElementById(id).replaceChildren()
    draw = SushiView.create(document, look, stage)
    const canvas = measure()
    flight = {
      ...SushiFlight.randomFlight(canvas, saying(), 'random', look),
      hoverX: canvas.width * (0.4 + Math.random() * 0.2),
      altitude: canvas.height * 0.6,
    }
    bubble.textContent = flight.message
    pets = []
    started = performance.now()
    if (still) {
      show(SushiFlight.FLY_IN + 0.8)
      return
    }
    frame = requestAnimationFrame(tick)
  }

  function show(time) {
    pose = SushiFlight.pose(flight, time)
    draw(pose, time, pets, SushiFlight.effects(flight, time))
    const lift = SushiLooks.bubbleLift(look, size)
    bubble.style.opacity = String(pose.bubble)
    bubble.style.transform = `translate(${pose.x}px, ${pose.y - size * 0.7 - lift}px) translate(-50%, -50%) scale(${0.6 + 0.4 * pose.bubble})`
  }

  function tick(now) {
    const time = (now - started) / 1000
    show(time)
    if (time < SushiFlight.DURATION) frame = requestAnimationFrame(tick)
    else again = setTimeout(rest, 2500)
  }

  // Flies again, but never while nobody can see it: then it waits for the sky to be back in view.
  let waiting = false
  function rest() {
    waiting = !inView || document.hidden
    if (!waiting) fly()
  }
  function wake() {
    if (waiting && inView && !document.hidden) {
      waiting = false
      fly()
    }
  }
  new IntersectionObserver(entries => {
    inView = entries[0].isIntersecting
    wake()
  }).observe(sky)
  document.addEventListener('visibilitychange', wake)

  function overSushi(event) {
    if (!pose || still) return false
    const box = sky.getBoundingClientRect()
    const x = (event.clientX - box.left - sky.clientLeft) / scale
    const y = (event.clientY - box.top - sky.clientTop) / scale
    return Math.hypot(x - pose.x, y - pose.y) < size * 0.42
  }
  sky.addEventListener('pointerdown', event => {
    if (overSushi(event)) pets.push((performance.now() - started) / 1000)
  })
  sky.addEventListener('pointermove', event => {
    sky.style.cursor = overSushi(event) ? 'pointer' : ''
  })

  document.getElementById('motivate').addEventListener('click', () => fly())

  for (const card of document.querySelectorAll('.look[data-look]')) {
    if (card.dataset.look === today.id) card.querySelector('.now').hidden = false
    card.addEventListener('click', () => {
      const box = sky.getBoundingClientRect()
      if (box.bottom < 0 || box.top > innerHeight - 80) {
        sky.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'center' })
      }
      fly(SushiLooks.named(looks, card.dataset.look))
    })
  }

  addEventListener('resize', () => {
    if (still && flight) fly()
    else measure()
  })

  setTimeout(() => fly(), 400)
})()
