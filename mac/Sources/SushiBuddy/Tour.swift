import CoreGraphics
import Foundation

/// A setting the tour offers to switch on, bound to Settings while the tour shows it.
struct TourSwitch {
    /// The setting's name, as in Settings.values and windows/settings.js.
    let key: String
    let label: String
    let isOn: (Settings) -> Bool
    let turn: (inout Settings, Bool) -> Void
    /// A sound to play when it's switched on, so you hear what you chose.
    var plays: String?

    /// On for any value but `off`. Switching on keeps a value you chose before and otherwise
    /// sets `on`; switching off sets `off`.
    static func setting<Value: Equatable>(
        _ key: String, _ path: WritableKeyPath<Settings, Value>, on: Value, off: Value, label: String, plays: String? = nil
    ) -> TourSwitch {
        TourSwitch(
            key: key,
            label: label,
            isOn: { $0[keyPath: path] != off },
            turn: { settings, isOn in
                if !isOn {
                    settings[keyPath: path] = off
                } else if settings[keyPath: path] == off {
                    settings[keyPath: path] = on
                }
            },
            plays: plays
        )
    }
}

/// One stop on the tour: what the sushi says, and what it offers.
struct TourStep {
    let id: String
    let text: String
    var switches: [TourSwitch] = []
    /// A command the step's button copies.
    var copies: String?
    /// The sushi does a loop-the-loop as the step opens.
    var showsLoop = false
    /// A page the step's button opens: What's New's last step links all the release notes.
    var link: URL?
}

/// The tour a new user gets: the sushi flies up next to its menu bar icon and, one step at a
/// time in its speech bubble, shows what it can do. The same steps and rules as windows/tour.js.
enum Tour {
    enum Platform { case mac, windows }

    static let claudeInstall = "claude plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy"

    /// `shortcut` is the label of the shortcut for Motivate me, or nil when it's off.
    static func steps(on platform: Platform, shortcut: String?) -> [TourStep] {
        let home = switch platform {
        case .mac: "That's me up there in the menu bar. Click me for Motivate me, a Pomodoro timer and Settings."
        case .windows: "That's me in the tray, by the clock (under ^ if Windows tucked me away). Click me there and I'll fly; right-click for Motivate me, a Pomodoro timer and Settings."
        }
        let quiet = switch platform {
        case .mac: "Don't worry: I keep away during a Focus, a call or anything full screen, and while you're away."
        case .windows: "Don't worry: I keep away during Do not disturb, a call or anything full screen, and while you're away."
        }
        return [
            TourStep(id: "hello", text: "Hi, I'm Sushi Buddy! 🍣 Let me show you around. It only takes a minute."),
            TourStep(id: "home", text: home),
            TourStep(
                id: "shortcut",
                text: shortcut.map { "Press \($0) anywhere and I'll fly by with something nice to say." }
                    ?? "Pick a shortcut in Settings and I'll fly by whenever you press it."
            ),
            TourStep(
                id: "pet",
                text: "Click me while I fly and I'll do a happy spin. Go on, try it!",
                switches: [.setting("petting", \.petting, on: true, off: false, label: "Let me pet you")]
            ),
            TourStep(
                id: "tricks",
                text: "I know tricks, too: loop-the-loops, bounces and zigzags.",
                switches: [.setting("sound", \.sound, on: "chime", off: "off", label: "Play a sound when you arrive", plays: "chime")],
                showsLoop: true
            ),
            TourStep(
                id: "onTheirOwn",
                text: "I can drop by on my own, too. Pick what you'd like; Settings has how often.",
                switches: [
                    .setting("autoMotivateSeconds", \.autoMotivateSeconds, on: 3600, off: 0, label: "Cheer me on every now and then"),
                    .setting("breakReminderMinutes", \.breakReminderMinutes, on: 60, off: 0, label: "Remind me to take breaks"),
                    .setting("welcomeBack", \.welcomeBack, on: true, off: false, label: "Welcome me back when I return"),
                ]
            ),
            TourStep(id: "quiet", text: quiet),
            TourStep(
                id: "claude",
                text: "Using Claude Code? I'll cheer when Claude finishes and fly over when it needs you. Run this once in a terminal to connect us:",
                copies: claudeInstall
            ),
            TourStep(id: "bye", text: "That's it! You'll find all of this, and the tour, in Settings. Have a great day! 🍣"),
        ]
    }

    /// Once for everyone, new or updating, and only at a moment an automatic flight could go.
    static func startsOnItsOwn(seen: Bool, quiet: QuietReason?) -> Bool {
        !seen && quiet == nil
    }

    /// Where the sushi waits: by its icon, kept inside the work area, with the bubble on the
    /// roomier side. Coordinates from the top left of the screen.
    struct Spot: Equatable {
        var x: CGFloat
        var y: CGFloat
        var bubbleOnLeft: Bool
        var bubbleBelow: Bool
    }

    static let sushiSize: CGFloat = 180

    /// `anchor`: the middle of the menu bar or tray icon, or a corner when it can't be found.
    static func place(anchor: CGPoint, in work: CGRect) -> Spot {
        let margin = sushiSize * 0.6
        let x = min(max(anchor.x, work.minX + margin), work.maxX - margin)
        let y = min(max(anchor.y, work.minY + margin), work.maxY - margin)
        return Spot(x: x, y: y, bubbleOnLeft: x > work.midX, bubbleBelow: y < work.midY)
    }

    /// The bubble's corner nearest the sushi: beside it, level with the top of the sushi when
    /// the bubble hangs down, or with its bottom when the bubble grows up.
    static func bubbleCorner(_ spot: Spot) -> CGPoint {
        CGPoint(
            x: spot.bubbleOnLeft ? spot.x - sushiSize * 0.55 : spot.x + sushiSize * 0.55,
            y: spot.bubbleBelow ? spot.y - sushiSize * 0.4 : spot.y + sushiSize * 0.4
        )
    }

    /// What takes clicks: the sushi and, while it shows, the bubble. Everything else passes through.
    static func isOver(_ point: CGPoint, sushi: CGPoint, bubble: CGRect) -> Bool {
        hypot(point.x - sushi.x, point.y - sushi.y) < sushiSize * 0.42 || bubble.contains(point)
    }

    static let loopSeconds: TimeInterval = 2

    /// The tour sushi's pose: the held flight's, plus a loop-the-loop for each `loops` start.
    static func pose(_ flight: Flight, at time: TimeInterval, loops: [TimeInterval]) -> Flight.Pose {
        var pose = flight.pose(at: time)
        let direction: Double = flight.isLeftToRight ? 1 : -1
        for start in loops where time >= start && time <= start + loopSeconds {
            let offset = FlightPath.loop.offset(isFlyIn: true, u: (time - start) / loopSeconds, direction: direction)
            pose.center.x += offset.dx
            pose.center.y += offset.dy
            pose.tilt += offset.spin
        }
        return pose
    }
}
