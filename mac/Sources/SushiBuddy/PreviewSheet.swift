import AppKit
import SwiftUI

/// `--preview <path> [--path loop] [--sushi santa]`: writes the sushi's own motion (the propeller's
/// turn, or a seasonal sushi a moment at a time) and a few moments of a flight to one PNG, for
/// checking the art without watching it. The last strip shows a pet.
@MainActor
enum PreviewSheet {
    static func write(to url: URL, path: FlightPath, look: Look = .classic) {
        let canvas = CGSize(width: 900, height: 420)
        let flight = Flight.preview(on: canvas, path: path, look: look)
        let moments = [0.9, flight.flyIn + 0.15, flight.flyIn + 1.0, flight.flyIn + 1.25, flight.flyIn + flight.hover + 0.7]
        let background = Color(red: 0.16, green: 0.17, blue: 0.2)
        let turns: [(label: String, time: TimeInterval)] = look.hasPropeller
            ? stride(from: 0.0, to: 360.0, by: 45.0).map { ("\(Int($0))°", $0 / 360 / SushiCopter.turnsPerSecond) }
            : stride(from: 0.0, to: 0.96, by: 0.12).map { (String(format: "%.2fs", $0), $0) }

        let sheet = VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(turns, id: \.time) { turn in
                    SushiCopter(look: look, time: turn.time, size: 112, pompom: flight.pose(at: turn.time).pompom)
                        .frame(width: canvas.width / 8)
                        .overlay(alignment: .bottom) {
                            Text(turn.label).foregroundStyle(.white)
                        }
                }
            }
            .frame(width: canvas.width, height: 160)
            .background(background)

            ForEach(moments, id: \.self) { time in
                FlightScene(flight: flight, time: time)
                    .background(background)
                    .overlay(alignment: .topLeading) {
                        Text(String(format: "%@ · %@, t = %.2fs", look.name, path.rawValue, time)).foregroundStyle(.white).padding(8)
                    }
            }

            FlightScene(flight: flight, time: flight.flyIn + 0.5, pets: [flight.flyIn + 0.2])
                .background(background)
                .overlay(alignment: .topLeading) {
                    Text("petted 0.3 s ago").foregroundStyle(.white).padding(8)
                }
        }

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
