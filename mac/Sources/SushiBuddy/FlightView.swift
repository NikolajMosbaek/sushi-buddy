import SwiftUI

struct FlightView: View {
    let model: FlightModel

    var body: some View {
        TimelineView(.animation) { timeline in
            FlightScene(flight: model.flight, time: timeline.date.timeIntervalSince(model.start), pets: model.pets)
        }
    }
}

/// The whole overlay at one instant, so a preview can render any moment of it.
struct FlightScene: View {
    let flight: Flight
    let time: TimeInterval
    var pets: [TimeInterval] = []

    var body: some View {
        let pose = flight.pose(at: time)
        let effects = flight.effects(at: time)

        ZStack(alignment: .topLeading) {
            Effects(effects: effects.filter { !$0.isInFront })
            PettedSushi(look: flight.look, pose: pose, time: time, pets: pets, size: flight.size)
            Effects(effects: effects.filter(\.isInFront))

            SpeechBubble(text: flight.message)
                .scaleEffect(0.6 + 0.4 * pose.bubble, anchor: .bottom)
                .opacity(pose.bubble)
                .position(x: pose.center.x, y: pose.center.y - flight.size * 0.7 - flight.look.bubbleLift(size: flight.size))
        }
        .frame(width: flight.canvas.width, height: flight.canvas.height)
        .ignoresSafeArea()
    }
}

/// What `Flight.effects` says to draw: emoji and words, and bubbles of foam.
struct Effects: View {
    let effects: [Flight.Effect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(effects.enumerated()), id: \.offset) { _, effect in
                Group {
                    if effect.glyph == "bubble" {
                        Circle()
                            .fill(.white)
                            .overlay { Circle().strokeBorder(Color(white: 0.55), lineWidth: 1.5) }
                            .frame(width: effect.size, height: effect.size)
                    } else if effect.isWord {
                        Text(effect.glyph)
                            .font(.system(size: effect.size, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white))
                            .overlay { Capsule().strokeBorder(Color(red: 0.1, green: 0.1, blue: 0.1), lineWidth: 2) }
                    } else {
                        Text(effect.glyph).font(.system(size: effect.size)).fixedSize()
                    }
                }
                .rotationEffect(.degrees(effect.rotation))
                .opacity(effect.opacity)
                .position(x: effect.x, y: effect.y)
            }
        }
    }
}

/// The sushi at one pose, with what its pets do to it. Fills the canvas it's placed on.
struct PettedSushi: View {
    var look: Look = .classic
    let pose: Flight.Pose
    let time: TimeInterval
    let pets: [TimeInterval]
    let size: CGFloat

    var body: some View {
        let reaction = PetReaction(pets: pets, time: time)

        ZStack(alignment: .topLeading) {
            SushiCopter(look: look, time: time, size: size, extraSpin: reaction.extraSpin, pompom: pose.pompom)
                .scaleEffect(reaction.squish)
                .rotationEffect(.degrees(pose.tilt))
                .position(pose.center)

            ForEach(Array(reaction.hearts.enumerated()), id: \.offset) { _, heart in
                Group {
                    if let glyph = look.petGlyph {
                        Text(glyph).font(.system(size: 26))
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.45))
                    }
                }
                .scaleEffect(0.6 + 0.6 * heart.progress)
                .opacity(1 - heart.progress)
                .position(x: pose.center.x + heart.dx, y: pose.center.y - size * 0.3 - 90 * heart.progress)
            }
        }
    }
}

/// What a pet does: two quick extra turns of the propeller, a squish, and hearts floating up.
/// windows/overlay.js does the same.
struct PetReaction {
    var extraSpin: Double = 0
    var squish: Double = 1
    var hearts: [(dx: Double, progress: Double)] = []

    init(pets: [TimeInterval], time: TimeInterval) {
        for pet in pets where time >= pet {
            let age = time - pet
            let spin = min(age / 0.9, 1)
            extraSpin += 720 * (1 - pow(1 - spin, 3))
            if age < 0.4 { squish = 1 + 0.18 * sin(.pi * age / 0.4) }
            if age < 1.2 {
                hearts += [-40.0, 0, 40].map { (dx: $0, progress: age / 1.2) }
            }
        }
    }
}

/// The sushi itself, `size` wide: the classic with its propeller turning, or a seasonal one, whose
/// image covers the larger stage around the same frame (with Santa's pompom swinging on its own).
struct SushiCopter: View {
    var look: Look = .classic
    let time: TimeInterval
    let size: CGFloat
    var extraSpin: Double = 0
    var pompom: Double = 0

    static let turnsPerSecond = 4.5

    var body: some View {
        ZStack {
            if look.hasPropeller {
                Image(nsImage: Artwork.body)
                    .resizable()
                    .interpolation(.high)
                Image(nsImage: Artwork.propeller)
                    .resizable()
                    .interpolation(.high)
                    .rotation3DEffect(
                        .degrees(time * 360 * Self.turnsPerSecond + extraSpin),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: UnitPoint(x: Artwork.propellerAxis.x, y: Artwork.propellerAxis.y),
                        perspective: 0.3
                    )
            } else {
                SeasonalSushi(look: look, size: size, pompom: pompom)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
    }
}

/// A seasonal sushi's images, which cover the stage (Looks.stage) around the classic 60×60 frame.
private struct SeasonalSushi: View {
    let look: Look
    let size: CGFloat
    let pompom: Double

    var body: some View {
        let stage = Looks.stage
        let side = size * stage.size / 60
        let shift = (stage.min + stage.size / 2 - 30) * size / 60
        ZStack {
            if let body = look.images["body"] {
                Image(nsImage: Artwork.image(file: body)).resizable().interpolation(.high)
            }
            if let file = look.images["pompom"], let top = look.points["pompomTop"] {
                Image(nsImage: Artwork.image(file: file))
                    .resizable()
                    .interpolation(.high)
                    .rotationEffect(
                        .degrees(pompom),
                        anchor: UnitPoint(x: (top.x - stage.min) / stage.size, y: (top.y - stage.min) / stage.size)
                    )
            }
        }
        .frame(width: side, height: side)
        .offset(x: shift, y: shift)
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
            .fixedSize()
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(red: 0.1, green: 0.1, blue: 0.1), lineWidth: 3)
                    }
            }
            .overlay(alignment: .bottom) {
                BubbleTail()
                    .fill(.white)
                    .overlay { BubbleTail().stroke(Color(red: 0.1, green: 0.1, blue: 0.1), lineWidth: 3) }
                    .frame(width: 22, height: 14)
                    .offset(y: 12.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
    }
}

/// A downward triangle, open at the top so it merges into the bubble's border.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
