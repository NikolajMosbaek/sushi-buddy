import CoreGraphics
import Foundation

/// One trip across the screen: fly in, hover while saying something nice, fly out.
struct Flight {
    let canvas: CGSize
    let message: String
    let isLeftToRight: Bool
    let hoverX: CGFloat
    let altitude: CGFloat

    let size: CGFloat = 180
    let flyIn: TimeInterval = 2.0
    let hover: TimeInterval = 3.2
    let flyOut: TimeInterval = 2.0

    var duration: TimeInterval { flyIn + hover + flyOut }

    static func random(on canvas: CGSize) -> Flight {
        Flight(
            canvas: canvas,
            message: Motivation.random(),
            isLeftToRight: Bool.random(),
            hoverX: canvas.width * .random(in: 0.35...0.65),
            altitude: canvas.height * .random(in: 0.3...0.6)
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
        switch time {
        case ..<flyIn:
            let u = time / flyIn
            x = startX + (hoverX - startX) * easeOut(u)
            lean = 12 * (1 - u)
        case ..<(flyIn + hover):
            x = hoverX + sin((time - flyIn) * 2 * .pi * 0.35) * 8
            lean = 0
        default:
            let u = min((time - flyIn - hover) / flyOut, 1)
            x = hoverX + (endX - hoverX) * easeIn(u)
            lean = 12 * u
        }

        return Pose(
            center: CGPoint(x: x, y: altitude + bob),
            tilt: Double(direction) * lean + wobble,
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
