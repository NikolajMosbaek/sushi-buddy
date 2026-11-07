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

        ZStack(alignment: .topLeading) {
            PettedSushi(pose: pose, time: time, pets: pets, size: flight.size)

            SpeechBubble(text: flight.message)
                .scaleEffect(0.6 + 0.4 * pose.bubble, anchor: .bottom)
                .opacity(pose.bubble)
                .position(x: pose.center.x, y: pose.center.y - flight.size * 0.7)
        }
        .frame(width: flight.canvas.width, height: flight.canvas.height)
        .ignoresSafeArea()
    }
}

/// The sushi at one pose, with what its pets do to it. Fills the canvas it's placed on.
struct PettedSushi: View {
    let pose: Flight.Pose
    let time: TimeInterval
    let pets: [TimeInterval]
    let size: CGFloat

    var body: some View {
        let reaction = PetReaction(pets: pets, time: time)

        ZStack(alignment: .topLeading) {
            SushiCopter(time: time, size: size, extraSpin: reaction.extraSpin)
                .scaleEffect(reaction.squish)
                .rotationEffect(.degrees(pose.tilt))
                .position(pose.center)

            ForEach(Array(reaction.hearts.enumerated()), id: \.offset) { _, heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.45))
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

struct SushiCopter: View {
    let time: TimeInterval
    let size: CGFloat
    var extraSpin: Double = 0

    static let turnsPerSecond = 4.5

    var body: some View {
        ZStack {
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
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
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
