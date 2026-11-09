import SwiftUI

struct TourView: View {
    let model: TourModel
    let preferences: Preferences

    var body: some View {
        TimelineView(.animation) { timeline in
            TourScene(model: model, preferences: preferences, time: timeline.date.timeIntervalSince(model.start))
        }
    }
}

/// The tour at one instant: the sushi by its icon, and the bubble with the step beside it.
/// The bubble stays put while the sushi bobs, so its buttons hold still under the mouse.
struct TourScene: View {
    let model: TourModel
    @Bindable var preferences: Preferences
    let time: TimeInterval

    var body: some View {
        let pose = Tour.pose(model.flight, at: time, loops: model.loops)
        let spot = model.spot
        let corner = Tour.bubbleCorner(spot)

        ZStack(alignment: .topLeading) {
            PettedSushi(look: model.flight.look, pose: pose, time: time, pets: model.pets, size: Tour.sushiSize)

            TourBubble(model: model, settings: $preferences.settings)
                .opacity(pose.bubble)
                .scaleEffect(0.9 + 0.1 * pose.bubble, anchor: UnitPoint(x: spot.bubbleOnLeft ? 1 : 0, y: spot.bubbleBelow ? 0 : 1))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tour")) } action: { model.bubbleFrame = $0 }
                .padding(spot.bubbleOnLeft ? .trailing : .leading, spot.bubbleOnLeft ? model.canvas.width - corner.x : corner.x)
                .padding(spot.bubbleBelow ? .top : .bottom, spot.bubbleBelow ? corner.y : model.canvas.height - corner.y)
                .frame(
                    width: model.canvas.width,
                    height: model.canvas.height,
                    alignment: Alignment(horizontal: spot.bubbleOnLeft ? .trailing : .leading, vertical: spot.bubbleBelow ? .top : .bottom)
                )
        }
        .coordinateSpace(.named("tour"))
        .frame(width: model.canvas.width, height: model.canvas.height)
        .ignoresSafeArea()
    }
}

/// One step in the sushi's speech bubble, with the step's switches and the way on.
struct TourBubble: View {
    let model: TourModel
    @Binding var settings: Settings

    static let ink = Color(red: 0.1, green: 0.1, blue: 0.1)

    var body: some View {
        let step = model.step
        let spot = model.spot

        VStack(alignment: .leading, spacing: 14) {
            Text(step.text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if !step.switches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(step.switches, id: \.key) { toggle in
                        Toggle(toggle.label, isOn: Binding(
                            get: { toggle.isOn(settings) },
                            set: { isOn in
                                toggle.turn(&settings, isOn)
                                if isOn, let sound = toggle.plays { Sound.play(sound) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
            }

            if let command = step.copies {
                TourButton(title: model.copied.contains(step.id) ? "Copied! Paste it in a terminal." : "Copy the install command") {
                    model.copy(command)
                }
            }

            if let link = step.link {
                TourButton(title: "All Release Notes") { model.open(link) }
            }

            HStack(spacing: 14) {
                if !model.isLast {
                    Button(model.closeTitle) { model.finish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.index + 1) of \(model.steps.count)")
                    .foregroundStyle(.secondary)
                if !model.isFirst {
                    TourButton(title: "Back", small: true) { model.back() }
                }
                TourButton(title: model.isLast ? "Done" : "Next", prominent: true) { model.next() }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Self.ink)
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .background {
            let shape = TourBubbleShape(tailOnRight: spot.bubbleOnLeft, tailFromTop: spot.bubbleBelow)
            shape.fill(.white).shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            shape.stroke(Self.ink, lineWidth: 3)
        }
        .environment(\.colorScheme, .light)
    }
}

/// The bubble's outline: a rounded box with a tail on the side facing the sushi, level with
/// the sushi's middle (`Tour.bubbleCorner` puts that 0.4 × its size from the bubble's top or bottom).
struct TourBubbleShape: Shape {
    let tailOnRight: Bool
    let tailFromTop: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let reach: CGFloat = 14
        let halfWidth: CGFloat = 11
        let level = Tour.sushiSize * 0.4
        let tailY = tailFromTop ? rect.minY + level : rect.maxY - level
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
        if tailOnRight {
            path.addLine(to: CGPoint(x: rect.maxX, y: tailY - halfWidth))
            path.addLine(to: CGPoint(x: rect.maxX + reach, y: tailY))
            path.addLine(to: CGPoint(x: rect.maxX, y: tailY + halfWidth))
        }
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
        if !tailOnRight {
            path.addLine(to: CGPoint(x: rect.minX, y: tailY + halfWidth))
            path.addLine(to: CGPoint(x: rect.minX - reach, y: tailY))
            path.addLine(to: CGPoint(x: rect.minX, y: tailY - halfWidth))
        }
        path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// The bubble's own buttons: drawn the same whether or not the panel is the key window.
struct TourButton: View {
    let title: String
    var prominent = false
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: small ? 12 : 14, weight: small ? .semibold : .bold, design: .rounded))
                .foregroundStyle(prominent ? .white : TourBubble.ink)
                .padding(.horizontal, small ? 10 : 14)
                .padding(.vertical, small ? 5 : 7)
                .background(
                    Pill()
                        .fill(prominent ? Color(red: 0.93, green: 0.4, blue: 0.3) : Color(white: 0.94))
                        .overlay(Pill().inset(by: 1).stroke(TourBubble.ink, lineWidth: 2))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A capsule drawn from two arcs. A stroked Capsule (or rounded-rect path) comes out of
/// --preview-tour's snapshots with stray bars at its ends; arcs draw the same everywhere.
struct Pill: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = rect.height / 2
        var path = Path()
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.midY), radius: radius, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.midY), radius: radius, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Pill { Pill(inset: inset + amount) }
}
