import AppKit
import SwiftUI

/// `--preview <path> [--path loop]`: writes the propeller's turn and a few moments of a flight
/// to one PNG, for checking the art without watching it. The last strip shows a pet.
@MainActor
enum PreviewSheet {
    static func write(to url: URL, path: FlightPath) {
        let canvas = CGSize(width: 900, height: 420)
        let flight = Flight.preview(on: canvas, path: path)
        let moments = [0.9, flight.flyIn + 1.0, flight.flyIn + flight.hover + 0.7]
        let angles = stride(from: 0.0, to: 360.0, by: 45.0).map { $0 }
        let background = Color(red: 0.16, green: 0.17, blue: 0.2)

        let sheet = VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(angles, id: \.self) { angle in
                    SushiCopter(time: angle / 360 / SushiCopter.turnsPerSecond, size: 112)
                        .overlay(alignment: .bottom) {
                            Text("\(Int(angle))°").foregroundStyle(.white)
                        }
                }
            }
            .frame(width: canvas.width, height: 140)
            .background(background)

            ForEach(moments, id: \.self) { time in
                FlightScene(flight: flight, time: time)
                    .background(background)
                    .overlay(alignment: .topLeading) {
                        Text(String(format: "%@, t = %.2fs", path.rawValue, time)).foregroundStyle(.white).padding(8)
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
