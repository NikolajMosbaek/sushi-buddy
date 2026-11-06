import SwiftUI

struct FlightView: View {
    let flight: Flight
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            FlightScene(flight: flight, time: timeline.date.timeIntervalSince(start))
        }
    }
}

/// The whole overlay at one instant, so a preview can render any moment of it.
struct FlightScene: View {
    let flight: Flight
    let time: TimeInterval

    var body: some View {
        let pose = flight.pose(at: time)

        ZStack(alignment: .topLeading) {
            SushiCopter(time: time, size: flight.size)
                .rotationEffect(.degrees(pose.tilt))
                .position(pose.center)

            SpeechBubble(text: flight.message)
                .scaleEffect(0.6 + 0.4 * pose.bubble, anchor: .bottom)
                .opacity(pose.bubble)
                .position(x: pose.center.x, y: pose.center.y - flight.size * 0.7)
        }
        .frame(width: flight.canvas.width, height: flight.canvas.height)
        .ignoresSafeArea()
    }
}

struct SushiCopter: View {
    let time: TimeInterval
    let size: CGFloat

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
                    .degrees(time * 360 * Self.turnsPerSecond),
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
