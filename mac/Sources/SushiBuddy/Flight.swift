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

    var duration: TimeInterval { flyIn + hover + flyOut }

    /// Ends the hover at `time`: the bubble fades, then the sushi flies off from where it is.
    mutating func letGo(at time: TimeInterval) {
        hover = max(time - flyIn, 0) + 0.35
    }

    static func random(on canvas: CGSize, message: String, path: FlightPath) -> Flight {
        Flight(
            canvas: canvas,
            message: message,
            path: path,
            isLeftToRight: Bool.random(),
            hoverX: canvas.width * .random(in: 0.35...0.65),
            altitude: canvas.height * .random(in: 0.3...0.6)
        )
    }

    static func preview(on canvas: CGSize, path: FlightPath = .classic) -> Flight {
        Flight(
            canvas: canvas,
            message: "You're on a roll! 🍣",
            path: path,
            isLeftToRight: true,
            hoverX: canvas.width / 2,
            altitude: canvas.height * 0.62
        )
    }

    struct Pose {
        var center: CGPoint
        var tilt: Double
        var bubble: Double
    }

    func pose(at time: TimeInterval) -> Pose {
        let direction: CGFloat = isLeftToRight ? 1 : -1
        let startX = isLeftToRight ? -size : canvas.width + size
        let endX = isLeftToRight ? canvas.width + size : -size
        let bob = sin(time * 2 * .pi * 0.9) * 14
        let wobble = sin(time * 2 * .pi * 0.6) * 3

        let x: CGFloat
        let lean: Double
        var offset: (dx: Double, dy: Double, spin: Double) = (0, 0, 0)
        switch time {
        case ..<flyIn:
            let u = time / flyIn
            x = startX + (hoverX - startX) * easeOut(u)
            lean = 12 * (1 - u)
            offset = path.offset(isFlyIn: true, u: u, direction: direction)
        case ..<(flyIn + hover):
            x = hoverX + sin((time - flyIn) * 2 * .pi * 0.35) * 8
            lean = 0
        default:
            // Leaves from where the hover's sway ended, so nothing jumps.
            let leaveX = hoverX + sin(hover * 2 * .pi * 0.35) * 8
            let u = min((time - flyIn - hover) / flyOut, 1)
            x = leaveX + (endX - leaveX) * easeIn(u)
            lean = 12 * u
            offset = path.offset(isFlyIn: false, u: u, direction: direction)
        }

        return Pose(
            center: CGPoint(x: x + offset.dx, y: altitude + bob + offset.dy),
            tilt: Double(direction) * lean + wobble + offset.spin,
            bubble: bubbleVisibility(at: time)
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
