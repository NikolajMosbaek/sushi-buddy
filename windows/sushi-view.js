// Draws the sushi at a pose, with what its pets do to it and what goes with it: the page's #sushi,
// #blades, #hearts and, where the page has them, #effects-back and #effects-front. The classic sushi
// turns its propeller; a seasonal one (looks.js) shows its own image, which covers the larger stage
// around the same frame, and Santa's pompom swings. Used by overlay.js (a flight) and tour-page.js
// (the tour), the way SushiCopter, PettedSushi and Effects in FlightView.swift are.
;(function (root) {
  const TURNS_PER_SECOND = 4.5

  /** `look` from looks.js; `stage` the square, in classic units, a seasonal sushi's images cover. */
  function create(document, look = root.SushiLooks.CLASSIC, stage = root.SushiLooks.STAGE) {
    const sushi = document.getElementById('sushi')
    const blades = document.getElementById('blades')
    const hearts = document.getElementById('hearts')
    const behind = document.getElementById('effects-back')
    const inFront = document.getElementById('effects-front')
    const size = root.SushiFlight.SIZE
    const petGlyph = root.SushiLooks.petGlyph(look) ?? '❤'

    let pompom = null
    const seasonal = !look.images.propeller
    if (seasonal) {
      const percent = units => `${(units / 60) * 100}%`
      const layer = file => {
        const image = document.createElement('img')
        image.src = `assets/${file}`
        image.alt = ''
        image.className = 'stage'
        Object.assign(image.style, { left: percent(stage.min), top: percent(stage.min), width: percent(stage.size), height: percent(stage.size) })
        return image
      }
      sushi.replaceChildren(layer(look.images.body))
      const top = look.points.pompomTop
      if (look.images.pompom && top) {
        pompom = layer(look.images.pompom)
        pompom.style.transformOrigin = `${((top.x - stage.min) / stage.size) * 100}% ${((top.y - stage.min) / stage.size) * 100}%`
        sushi.append(pompom)
      }
    }

    return function draw(pose, time, pets, effects = []) {
      const { extraSpin, squish, hearts: floating } = root.SushiFlight.petReaction(pets, time)
      sushi.style.transform =
        `translate(${pose.x - size / 2}px, ${pose.y - size / 2}px) rotate(${pose.tilt}deg) scale(${squish})`
      if (!seasonal) blades.style.transform = `perspective(540px) rotateY(${time * 360 * TURNS_PER_SECOND + extraSpin}deg)`
      if (pompom) pompom.style.transform = `rotate(${pose.pompom ?? 0}deg)`

      while (hearts.children.length < floating.length) {
        const heart = document.createElement('div')
        heart.className = 'heart'
        heart.textContent = petGlyph
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

      if (behind) drawEffects(document, behind, effects.filter(effect => !effect.isInFront))
      if (inFront) drawEffects(document, inFront, effects.filter(effect => effect.isInFront))
    }
  }

  /** What SushiFlight.effects says to draw: emoji, words in a little white label, bubbles of foam. */
  function drawEffects(document, container, effects) {
    while (container.children.length < effects.length) container.append(document.createElement('div'))
    Array.from(container.children).forEach((element, index) => {
      const effect = effects[index]
      element.style.display = effect ? 'block' : 'none'
      if (!effect) return
      const kind = effect.glyph === 'bubble' ? 'foam' : effect.isWord ? 'word' : 'emoji'
      element.className = `effect ${kind}`
      if (kind === 'foam') {
        element.textContent = ''
        element.style.width = element.style.height = `${effect.size}px`
      } else {
        element.textContent = effect.glyph
        element.style.fontSize = `${effect.size}px`
      }
      element.style.opacity = String(effect.opacity)
      element.style.transform = `translate(${effect.x}px, ${effect.y}px) translate(-50%, -50%) rotate(${effect.rotation}deg)`
    })
  }

  root.SushiView = { create }
})(this)
