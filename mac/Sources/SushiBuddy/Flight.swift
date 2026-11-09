import CoreGraphics
import Foundation

/// The ways across the screen. Each strays from the straight line only on the way in or
/// out, and is back on it where the hover starts and ends.
enum FlightPath: String, CaseIterable, Sendable {
    case classic, loop, bounce, zigzag

    /// A path by its Settings name; "random" (or anything unknown) picks one.
    static func named(_ name: String) -> FlightPath {
        FlightPath(rawValue: name) ?? allCases.randomElement() ?? .classic
    }

    /// How far the path strays at progress `u` (0…1) of the fly-in or fly-out; `spin` in degrees.
    func offset(isFlyIn: Bool, u: Double, direction: Double) -> (dx: Double, dy: Double, spin: Double) {
        switch self {
        case .classic:
            return (0, 0, 0)
        case .loop:
            guard isFlyIn else { return (0, 0, 0) }
            let angle = 2 * .pi * Self.smoothstep(min(max((u - 0.25) / 0.5, 0), 1))
            return (direction * 70 * sin(angle), -70 * (1 - cos(angle)), -direction * angle * 180 / .pi)
        case .bounce:
            return (0, -abs(sin(u * .pi * 3)) * 80 * (isFlyIn ? 1 - u : u), 0)
        case .zigzag:
            return (0, sin(u * .pi * 4) * 60 * (isFlyIn ? 1 - u : u), 0)
        }
    }

    private static func smoothstep(_ u: Double) -> Double { u * u * (3 - 2 * u) }
}

/// One trip across the screen: fly in, hover while saying something nice, fly out.
/// windows/flight.js is a line-for-line port, so both apps move alike.
struct Flight {
    let canvas: CGSize
    let message: String
    var path: FlightPath = .classic
    let isLeftToRight: Bool
    let hoverX: CGFloat
    let altitude: CGFloat

    let size: CGFloat = 180
    let flyIn: TimeInterval = 2.0
    /// The tour holds the hover (`.infinity`) until it lets go.
    var hover: TimeInterval = 3.2
    let flyOut: TimeInterval = 2.0

    /// Which sushi flies; each seasonal one moves its own way (see `pose` and `effects`).
    var look: Look = .classic

    var duration: TimeInterval { flyIn + hover + flyOut }

    /// Ends the hover at `time`: the bubble fades, then the sushi flies off from where it is.
    mutating func letGo(at time: TimeInterval) {
        hover = max(time - flyIn, 0) + 0.35
    }

    static func random(on canvas: CGSize, message: String, path: FlightPath, look: Look = .classic) -> Flight {
        Flight(
            canvas: canvas,
            message: message,
            path: path,
            isLeftToRight: Bool.random(),
            hoverX: canvas.width * .random(in: 0.35...0.65),
            altitude: canvas.height * .random(in: 0.3...0.6),
            look: look
        )
    }

    static func preview(on canvas: CGSize, path: FlightPath = .classic, look: Look = .classic) -> Flight {
        Flight(
            canvas: canvas,
            message: "You're on a roll! 🍣",
            path: path,
            isLeftToRight: true,
            hoverX: canvas.width / 2,
            altitude: canvas.height * 0.62,
            look: look
        )
    }

    struct Pose {
        var center: CGPoint
        var tilt: Double
        var bubble: Double
        /// Santa's pompom, swinging from the tip of the hat, in degrees.
        var pompom: Double = 0
    }

    /// Where the sushi is at `time`. The seasonal ones move their own way: the Fall sushi floats slowly,
    /// swaying under its umbrella; the Easter Bunny hops instead of following the path; Metalhead
    /// headbangs while it hovers; Santa's pompom swings behind it.
    func pose(at time: TimeInterval) -> Pose {
        let direction: CGFloat = isLeftToRight ? 1 : -1
        let startX = isLeftToRight ? -size : canvas.width + size
        let endX = isLeftToRight ? canvas.width + size : -size
        var bob = sin(time * 2 * .pi * 0.9) * 14
        var wobble = sin(time * 2 * .pi * 0.6) * 3
        if look.id == "fall" {
            bob = sin(time * 2 * .pi * 0.5) * 18
            wobble = sin(time * 2 * .pi * 0.5 + .pi / 2) * 7
        }

        let x: CGFloat
        let lean: Double
        var offset: (dx: Double, dy: Double, spin: Double) = (0, 0, 0)
        switch time {
        case ..<flyIn:
            let u = time / flyIn
            x = startX + (hoverX - startX) * easeOut(u)
            lean = 12 * (1 - u)
            offset = look.id == "bunny" ? hop(u: u, isFlyIn: true) : path.offset(isFlyIn: true, u: u, direction: direction)
        case ..<(flyIn + hover):
            x = hoverX + sin((time - flyIn) * 2 * .pi * 0.35) * 8
            lean = 0
            if look.id == "bunny" { offset.dy = -max(0, sin((time - flyIn) * 2 * .pi * 1.1)) * 16 * settle(at: time) }
        default:
            // Leaves from where the hover's sway ended, so nothing jumps.
            let leaveX = hoverX + sin(hover * 2 * .pi * 0.35) * 8
            let u = min((time - flyIn - hover) / flyOut, 1)
            x = leaveX + (endX - leaveX) * easeIn(u)
            lean = 12 * u
            offset = look.id == "bunny" ? hop(u: u, isFlyIn: false) : path.offset(isFlyIn: false, u: u, direction: direction)
        }
        if look.id == "bunny" { bob = 0 }

        var pose = Pose(
            center: CGPoint(x: x + offset.dx, y: altitude + bob + offset.dy),
            tilt: Double(direction) * lean + wobble + offset.spin,
            bubble: bubbleVisibility(at: time)
        )
        if look.id == "metalhead" {
            // Nods from the bottom of the rice, so the head does the moving.
            let angle = headbang(at: time)
            let pivot = size * 0.38
            pose.center.x += pivot * sin(angle * .pi / 180)
            pose.center.y += pivot * (1 - cos(angle * .pi / 180))
            pose.tilt += angle
        }
        if look.id == "santa" {
            pose.pompom = sin(time * 2 * .pi * 1.3) * 18 - Double(direction) * lean * 1.2
        }
        return pose
    }

    /// The Easter Bunny's hops across the screen, highest far out and settling as it arrives.
    private func hop(u: Double, isFlyIn: Bool) -> (dx: Double, dy: Double, spin: Double) {
        (0, -abs(sin(u * .pi * 4)) * 55 * (isFlyIn ? 1 - u : u), 0)
    }

    /// Metalhead's nod in degrees: only while it hovers, easing in and out so nothing jumps.
    private func headbang(at time: TimeInterval) -> Double {
        sin((time - flyIn) * 2 * .pi * 2.2) * 14 * settle(at: time)
    }

    /// 0 outside the hover, rising to 1 in its first 0.4 s and back to 0 in its last: how much of a
    /// move made while hovering shows, so it starts and stops where the hover does.
    private func settle(at time: TimeInterval) -> Double {
        let into = time - flyIn
        guard into > 0, into < hover else { return 0 }
        return min(1, into / 0.4, (hover - into) / 0.4)
    }

    /// Something drawn with the sushi at a point of the canvas: an emoji (a leaf, a snowflake, a
    /// spark), a word in a little white label (`isWord`), or a bubble of foam (`glyph` "bubble").
    /// `isInFront` of the sushi or behind it.
    struct Effect: Equatable {
        var glyph: String
        var x: Double
        var y: Double
        var size: Double
        var rotation: Double = 0
        var opacity: Double = 1
        var isInFront = true
        var isWord = false
    }

    /// What goes with the sushi at `time`: the Fall sushi's leaves blowing past, J-Day's snow and the foam
    /// from its can as it arrives, Santa's trail of sparkles, the egg the Easter Bunny drops, and
    /// Metalhead's trail of flames and its horns while it headbangs. The classic has none.
    func effects(at time: TimeInterval) -> [Effect] {
        let pose = pose(at: time)
        let center = pose.center
        let direction: Double = isLeftToRight ? 1 : -1
        let moving = { (time: TimeInterval) in time >= 0 && (time < flyIn || time > flyIn + hover) }
        let fraction = { (value: Double) in value - floor(value) }

        switch look.id {
        case "fall":
            return (0..<3).map { leaf in
                let q = fraction(time / 2.6 + Double(leaf) / 3)
                return Effect(
                    glyph: leaf == 1 ? "🍁" : "🍂",
                    x: center.x + direction * size * (0.9 - 1.8 * q),
                    y: center.y - size * 0.25 + size * 0.55 * q + sin(q * 2 * .pi * 1.5 + Double(leaf)) * size * 0.06,
                    size: 30,
                    rotation: q * 480 * (leaf.isMultiple(of: 2) ? 1 : -1),
                    opacity: sin(q * .pi)
                )
            }
        case "jday":
            var effects = (0..<10).map { flake in
                let q = fraction(time / 3.2 + Double(flake) * 0.37)
                return Effect(
                    glyph: "❄️",
                    x: center.x + (Double(flake) / 9 - 0.5) * size * 1.8 + sin(time * 1.3 + Double(flake)) * 10,
                    y: center.y - size * 0.85 + q * size * 1.5,
                    size: 14 + Double(flake % 3) * 4,
                    rotation: time * 40 + Double(flake) * 30,
                    opacity: sin(q * .pi) * 0.95,
                    isInFront: flake.isMultiple(of: 2)
                )
            }
            if let can = point("can", pose: pose) {
                let opened = flyIn - 0.1
                for bubble in 0..<7 {
                    let age = time - opened - Double(bubble) * 0.12
                    guard age > 0, age < 1.1 else { continue }
                    let q = age / 1.1
                    effects.append(Effect(
                        glyph: "bubble",
                        x: can.x + sin(age * 9 + Double(bubble)) * 6 + Double(bubble % 3 - 1) * 6,
                        y: can.y - q * size * 0.35,
                        size: 8 + Double(bubble % 3) * 3,
                        opacity: 1 - q
                    ))
                }
                let age = time - opened
                if age > 0, age < 1.0 {
                    effects.append(Effect(
                        glyph: "pssht!", x: can.x + 30, y: can.y - size * 0.3, size: 18, rotation: -8, opacity: 1 - age, isWord: true
                    ))
                }
            }
            return effects
        case "santa":
            return (1...6).compactMap { spark in
                let then = time - Double(spark) * 0.08
                guard moving(then) else { return nil }
                let trail = self.pose(at: then).center
                return Effect(
                    glyph: "✨",
                    x: trail.x,
                    y: trail.y + size * 0.1,
                    size: 32 - Double(spark) * 2,
                    rotation: Double(spark) * 25,
                    opacity: 1 - Double(spark) / 8,
                    isInFront: false
                )
            }
        case "bunny":
            let dropped = flyIn + 0.8
            let age = time - dropped
            guard age >= 0, age < 1.6, let basket = point("basket", pose: self.pose(at: dropped)) else { return [] }
            let gravity = size * 6
            let fall = size * 0.55
            let landed = sqrt(2 * fall / gravity)
            var drop = age < landed ? 0.5 * gravity * age * age : fall
            if age >= landed {
                let since = age - landed
                drop -= max(0, 0.35 * sqrt(2 * gravity * fall) * since - 0.5 * gravity * since * since)
            }
            return [Effect(
                glyph: "🥚",
                x: basket.x + age * direction * size * 0.15,
                y: basket.y + drop,
                size: 26,
                rotation: min(age, landed) * 200,
                opacity: age > 1.2 ? 1 - (age - 1.2) / 0.4 : 1
            )]
        case "metalhead":
            var effects = (1...5).compactMap { flame -> Effect? in
                let then = time - Double(flame) * 0.07
                guard moving(then) else { return nil }
                let trail = self.pose(at: then).center
                return Effect(
                    glyph: "🔥",
                    x: trail.x - direction * size * 0.15,
                    y: trail.y + size * 0.15,
                    size: 34 - Double(flame) * 2,
                    opacity: 1 - Double(flame) / 7,
                    isInFront: false
                )
            }
            let nod = abs(headbang(at: time)) / 14
            if nod > 0 {
                effects.append(Effect(
                    glyph: "🤘",
                    x: center.x - direction * size * 0.55,
                    y: center.y - size * 0.1 - nod * 8,
                    size: 30,
                    opacity: settle(at: time)
                ))
            }
            return effects
        default:
            return []
        }
    }

    /// A named point of the art (see Look), where it is on the canvas at `pose`, tilt included.
    func point(_ name: String, pose: Pose) -> CGPoint? {
        guard let offset = look.offset(of: name, size: size) else { return nil }
        let angle = pose.tilt * .pi / 180
        return CGPoint(
            x: pose.center.x + offset.x * cos(angle) - offset.y * sin(angle),
            y: pose.center.y + offset.x * sin(angle) + offset.y * cos(angle)
        )
    }

    private func bubbleVisibility(at time: TimeInterval) -> Double {
        let appear = flyIn - 0.3
        let vanish = flyIn + hover
        if time < appear || time > vanish { return 0 }
        return min(min((time - appear) / 0.35, (vanish - time) / 0.35), 1)
    }

    private func easeOut(_ u: Double) -> Double { 1 - pow(1 - u, 3) }
    private func easeIn(_ u: Double) -> Double { u * u * u }
}
