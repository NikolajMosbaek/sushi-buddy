import AppKit
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "flight")

/// The pets a flight has had, as seconds into it, so the view can react.
@MainActor
@Observable
final class FlightModel {
    let flight: Flight
    let start: Date
    private(set) var pets: [TimeInterval] = []

    init(flight: Flight, start: Date) {
        self.flight = flight
        self.start = start
    }

    var time: TimeInterval { Date.now.timeIntervalSince(start) }

    func pet() { pets.append(time) }
}

/// Takes clicks without making the app active, so a pet doesn't steal focus from your work.
final class PettableHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

@MainActor
final class FlightController {
    /// Each flight is held until it lands; a dropped panel vanishes mid-air.
    private var flights: [(panel: NSPanel, timer: Timer?)] = []
    var onPet: (() -> Void)?

    /// The screen your mouse is on.
    var currentScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    /// `petting`: the sushi itself takes clicks (everything around it still passes through).
    func launch(_ flight: Flight, on screen: NSScreen, petting: Bool, sound: String) {
        let model = FlightModel(flight: flight, start: .now)
        let panel = makePanel(on: screen)
        let host = PettableHostingView(rootView: FlightView(model: model))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.setFrame(screen.frame, display: true)

        var timer: Timer?
        if petting {
            let isOver: @MainActor () -> Bool = { [weak panel] in
                guard let panel else { return false }
                return Self.isOverSushi(NSEvent.mouseLocation, flight: flight, at: model.time, in: panel.frame)
            }
            host.onMouseDown = { [weak self] in
                guard isOver() else { return }
                model.pet()
                self?.onPet?()
            }
            // The panel lets clicks through except while the mouse is on the sushi.
            let poll = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak panel] _ in
                MainActor.assumeIsolated {
                    guard let panel else { return }
                    let ignore = !isOver()
                    if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
                }
            }
            RunLoop.main.add(poll, forMode: .common)
            timer = poll
        }

        // macOS naps an app it thinks no one is looking at (a locked screen, say), which
        // can hold the landing back by minutes and leave the panel up.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "A sushi is flying")
        panel.orderFrontRegardless()
        flights.append((panel, timer))
        Sound.accompany(flight, with: sound)
        logger.notice("flight (\(flight.path.rawValue, privacy: .public)) on \(screen.localizedName, privacy: .public): \(flight.message, privacy: .public)")

        Task {
            try? await Task.sleep(for: .seconds(flight.duration + 0.2))
            timer?.invalidate()
            panel.orderOut(nil)
            flights.removeAll { $0.panel === panel }
            ProcessInfo.processInfo.endActivity(activity)
            logger.notice("flight landed")
        }
    }

    /// `mouse` in screen coordinates (origin bottom left); the flight draws from the top left of `frame`.
    nonisolated static func isOverSushi(_ mouse: CGPoint, flight: Flight, at time: TimeInterval, in frame: CGRect) -> Bool {
        let center = flight.pose(at: time).center
        let x = frame.minX + center.x
        let y = frame.maxY - center.y
        return hypot(mouse.x - x, mouse.y - y) < flight.size * 0.42
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
