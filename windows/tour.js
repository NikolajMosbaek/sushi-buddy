// The tour a new user gets: the sushi flies up next to its tray icon and, one step at a time
// in its speech bubble, shows what it can do. The same steps and rules as
// mac/Sources/SushiBuddy/Tour.swift. Loaded by main.js (require) and by tour.html (<script>).
;(function (root) {
  const CLAUDE_INSTALL = 'claude plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy'
  const SUSHI_SIZE = 180
  const LOOP_SECONDS = 2
  const flights = typeof module === 'object' && module.exports ? require('./flight') : root.SushiFlight

  /**
   * A setting the tour offers to switch on. On for any value but `off`; switching on keeps a
   * value you chose before and otherwise sets `on`; switching off sets `off`.
   */
  const setting = (key, on, off, label, plays) => ({ key, on, off, label, plays })

  const isOn = (toggle, settings) => settings[toggle.key] !== toggle.off

  /** The value to store when `toggle` is switched to `on`. */
  function valueFor(toggle, settings, on) {
    if (!on) return toggle.off
    return isOn(toggle, settings) ? settings[toggle.key] : toggle.on
  }

  /** `platform` is 'mac' or 'windows'; `shortcut` the label of Motivate me's shortcut, or null when it's off. */
  function steps(platform, shortcut) {
    const home =
      platform === 'mac'
        ? "That's me up there in the menu bar. Click me for Motivate me, a Pomodoro timer and Settings."
        : "That's me in the tray, by the clock (under ^ if Windows tucked me away). Click me there and I'll fly; right-click for Motivate me, a Pomodoro timer and Settings."
    const quiet =
      platform === 'mac'
        ? "Don't worry: I keep away during a Focus, a call or anything full screen, and while you're away."
        : "Don't worry: I keep away during Do not disturb, a call or anything full screen, and while you're away."
    return [
      { id: 'hello', text: "Hi, I'm Sushi Buddy! 🍣 Let me show you around. It only takes a minute." },
      { id: 'home', text: home },
      {
        id: 'shortcut',
        text: shortcut
          ? `Press ${shortcut} anywhere and I'll fly by with something nice to say.`
          : "Pick a shortcut in Settings and I'll fly by whenever you press it.",
      },
      {
        id: 'pet',
        text: "Click me while I fly and I'll do a happy spin. Go on, try it!",
        switches: [setting('petting', true, false, 'Let me pet you')],
      },
      {
        id: 'tricks',
        text: 'I know tricks, too: loop-the-loops, bounces and zigzags.',
        switches: [setting('sound', 'chime', 'off', 'Play a sound when you arrive', 'chime')],
        showsLoop: true,
      },
      {
        id: 'onTheirOwn',
        text: "I can drop by on my own, too. Pick what you'd like; Settings has how often.",
        switches: [
          setting('autoMotivateSeconds', 3600, 0, 'Cheer me on every now and then'),
          setting('breakReminderMinutes', 60, 0, 'Remind me to take breaks'),
          setting('welcomeBack', true, false, 'Welcome me back when I return'),
        ],
      },
      { id: 'quiet', text: quiet },
      {
        id: 'claude',
        text: "Using Claude Code? I'll cheer when Claude finishes and fly over when it needs you. Run this once in a terminal to connect us:",
        copies: CLAUDE_INSTALL,
      },
      shareStep(),
      { id: 'bye', text: "That's it! You'll find all of this, and the tour, in Settings. Have a great day! 🍣" },
    ].map(step => ({ switches: [], copies: null, showsLoop: false, ...step }))
  }

  /** The one time the sushi asks to share usage statistics: in the tour, or at the end of What's New. */
  function shareStep() {
    return {
      id: 'share',
      text: "One more thing: may I tell Nikolaj, who made me, how I'm used? Once a day and anonymously: your settings and how often I flew, never anything you typed. Settings shows exactly what's sent.",
      switches: [setting('shareUsage', true, false, 'Share anonymous usage statistics')],
      copies: null,
      showsLoop: false,
      link: null,
    }
  }

  /** Once for everyone, new or updating, and only at a moment an automatic flight could go. */
  const startsOnItsOwn = (seen, quietReason) => !seen && quietReason == null

  /**
   * Where the sushi waits: by its icon (`anchor`, its middle, or a corner when it can't be
   * found), kept inside the work area, with the bubble on the roomier side. Coordinates from
   * the top left of the screen; `work` is { x, y, width, height }.
   */
  function place(anchor, work) {
    const margin = SUSHI_SIZE * 0.6
    const x = Math.min(Math.max(anchor.x, work.x + margin), work.x + work.width - margin)
    const y = Math.min(Math.max(anchor.y, work.y + margin), work.y + work.height - margin)
    return { x, y, bubbleOnLeft: x > work.x + work.width / 2, bubbleBelow: y < work.y + work.height / 2 }
  }

  /** The bubble's corner nearest the sushi: beside it, level with its top (bubble hangs down) or bottom (grows up). */
  function bubbleCorner(spot) {
    return {
      x: spot.bubbleOnLeft ? spot.x - SUSHI_SIZE * 0.55 : spot.x + SUSHI_SIZE * 0.55,
      y: spot.bubbleBelow ? spot.y - SUSHI_SIZE * 0.4 : spot.y + SUSHI_SIZE * 0.4,
    }
  }

  /** What takes clicks: the sushi and, while it shows, the bubble ({ x, y, width, height } or null). */
  function isOver(point, sushi, bubble) {
    if (Math.hypot(point.x - sushi.x, point.y - sushi.y) < SUSHI_SIZE * 0.42) return true
    return bubble != null && point.x >= bubble.x && point.x <= bubble.x + bubble.width && point.y >= bubble.y && point.y <= bubble.y + bubble.height
  }

  /** The tour sushi's pose: the held flight's, plus a loop-the-loop for each `loops` start. */
  function tourPose(flight, time, loops) {
    const pose = flights.pose(flight, time)
    const direction = flight.isLeftToRight ? 1 : -1
    for (const start of loops) {
      if (time < start || time > start + LOOP_SECONDS) continue
      const offset = flights.pathOffset('loop', true, (time - start) / LOOP_SECONDS, direction)
      pose.x += offset.dx
      pose.y += offset.dy
      pose.tilt += offset.spin
    }
    return pose
  }

  const api = { CLAUDE_INSTALL, SUSHI_SIZE, LOOP_SECONDS, steps, shareStep, isOn, valueFor, startsOnItsOwn, place, bubbleCorner, isOver, tourPose }
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.SushiTour = api
})(this)
