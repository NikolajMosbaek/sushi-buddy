import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "flight")

@MainActor
final class FlightController {
    /// Each panel is held until its flight lands; a dropped panel vanishes mid-air.
    private var panels: [NSPanel] = []

    func launch() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            logger.error("no screen to fly on")
            return
        }

        let flight = Flight.random(on: screen.frame.size)
        let panel = makePanel(on: screen)
        let host = NSHostingView(rootView: FlightView(flight: flight, start: .now))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        panels.append(panel)
        logger.notice("flight started on \(screen.localizedName, privacy: .public): \(flight.message, privacy: .public)")

        Task {
            try? await Task.sleep(for: .seconds(flight.duration + 0.2))
            panel.orderOut(nil)
            panels.removeAll { $0 === panel }
            logger.notice("flight landed")
        }
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
