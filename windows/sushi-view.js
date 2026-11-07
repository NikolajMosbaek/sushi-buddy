// Draws the sushi at a pose, its propeller turning, with what its pets do to it: the page's
// #sushi, #blades and #hearts. Used by overlay.js (a flight) and tour-page.js (the tour), the
// way PettedSushi in FlightView.swift is.
;(function (root) {
  const TURNS_PER_SECOND = 4.5

  function create(document) {
    const sushi = document.getElementById('sushi')
    const blades = document.getElementById('blades')
    const hearts = document.getElementById('hearts')
    const size = root.SushiFlight.SIZE

    return function draw(pose, time, pets) {
      const { extraSpin, squish, hearts: floating } = root.SushiFlight.petReaction(pets, time)
      sushi.style.transform =
        `translate(${pose.x - size / 2}px, ${pose.y - size / 2}px) rotate(${pose.tilt}deg) scale(${squish})`
      blades.style.transform = `perspective(540px) rotateY(${time * 360 * TURNS_PER_SECOND + extraSpin}deg)`

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
    }
  }

  root.SushiView = { create }
})(this)
