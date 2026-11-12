import AppKit
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "tour")

/// The tour while it runs: the step it's on, and what the sushi has been asked to do.
@MainActor
@Observable
final class TourModel {
    let steps: [TourStep]
    let spot: Tour.Spot
    let canvas: CGSize
    let start: Date
    /// The way out before the last step: "Skip tour", or What's New's "Close".
    let closeTitle: String
    private(set) var flight: Flight
    private(set) var index = 0
    private(set) var pets: [TimeInterval] = []
    private(set) var loops: [TimeInterval] = []
    private(set) var copied: Set<String> = []
    /// The bubble as drawn, from the top left of the panel, for the click test.
    @ObservationIgnored var bubbleFrame: CGRect = .null
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var onShow: ((TourStep) -> Void)?

    init(steps: [TourStep], spot: Tour.Spot, canvas: CGSize, closeTitle: String = "Skip tour", look: Look = .classic, start: Date = .now) {
        self.steps = steps
        self.spot = spot
        self.canvas = canvas
        self.closeTitle = closeTitle
        self.start = start
        // In from the far side, so the sushi crosses the screen to its icon, and out the near side.
        flight = Flight(
            canvas: canvas, message: "", isLeftToRight: spot.bubbleOnLeft, hoverX: spot.x, altitude: spot.y, hover: .infinity, look: look
        )
    }

    var time: TimeInterval { Date.now.timeIntervalSince(start) }
    var step: TourStep { steps[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    var isLeaving: Bool { flight.hover != .infinity }

    func pet() { pets.append(time) }

    func next() {
        guard !isLeaving else { return }
        guard !isLast else { return finish() }
        go(by: 1)
    }

    func back() {
        guard !isLeaving, !isFirst else { return }
        go(by: -1)
    }

    /// Coming to the tricks step, from either side, shows a loop-the-loop.
    private func go(by offset: Int) {
        index += offset
        if step.showsLoop { loops.append(time + 0.2) }
        onShow?(step)
    }

    func finish() {
        guard !isLeaving else { return }
        flight.letGo(at: time)
        onFinish?()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied.insert(step.id)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// A panel that can take the bubble's clicks without making the app active, the way
/// Spotlight does, so buttons and checkboxes answer on the first click.
final class TourPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hands every click on to SwiftUI, after telling the tour about it (for pets).
final class TourHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// Runs the tour: a panel over the screen with the menu bar icon, which lets clicks through
/// except on the sushi and its bubble.
@MainActor
final class TourController {
    private var running: (panel: NSPanel, model: TourModel, poll: Timer, activity: NSObjectProtocol)?

    var isRunning: Bool { running != nil }
    /// Each step as the bubble comes to it.
    var onShow: ((TourStep) -> Void)?

    /// Whether it started: not while the bubble already shows (the tour, or What's New).
    @discardableResult
    func start(steps: [TourStep], preferences: Preferences, closeTitle: String = "Skip tour") -> Bool {
        guard running == nil, let place = Self.whereToWait() else { return false }
        let frame = place.screen.frame
        let model = TourModel(
            steps: steps, spot: place.spot, canvas: frame.size, closeTitle: closeTitle, look: Looks.current(preferences.settings.sushi)
        )

        let panel = TourPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = TourHostingView(rootView: TourView(model: model, preferences: preferences))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.setFrame(frame, display: true)

        let mouse: @MainActor () -> CGPoint = {
            let location = NSEvent.mouseLocation
            return CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y)
        }
        let sushi: @MainActor () -> CGPoint = { Tour.pose(model.flight, at: model.time, loops: model.loops).center }
        host.onMouseDown = {
            if hypot(mouse().x - sushi().x, mouse().y - sushi().y) < Tour.sushiSize * 0.42 { model.pet() }
        }
        // The panel lets clicks through except over the sushi and the bubble while it shows.
        let poll = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                let bubble = model.flight.pose(at: model.time).bubble > 0.5 ? model.bubbleFrame : .null
                let ignore = !Tour.isOver(mouse(), sushi: sushi(), bubble: bubble)
                if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
            }
        }
        RunLoop.main.add(poll, forMode: .common)

        model.onShow = { [weak self] step in self?.onShow?(step) }
        let flightOff = 0.35 + model.flight.flyOut + 0.3
        model.onFinish = { [weak self] in
            Task {
                try? await Task.sleep(for: .seconds(flightOff))
                self?.close()
            }
        }
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Showing the tour")
        panel.orderFrontRegardless()
        running = (panel, model, poll, activity)
        logger.notice("tour started on \(place.screen.localizedName, privacy: .public)")
        return true
    }

    /// A flight asked for during the tour: the tour sushi spins instead of a second one flying.
    func react() {
        running?.model.pet()
    }

    private func close() {
        guard let running else { return }
        running.poll.invalidate()
        running.panel.orderOut(nil)
        ProcessInfo.processInfo.endActivity(running.activity)
        self.running = nil
        logger.notice("tour ended at step \(running.model.step.id, privacy: .public)")
    }

    /// The screen with the menu bar icon and where on it the sushi waits: by the icon, or in
    /// the top right corner when the icon can't be found.
    private static func whereToWait() -> (screen: NSScreen, spot: Tour.Spot)? {
        let icon = NSApp.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" }?.frame
        let found = icon.flatMap { icon in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: icon.midX, y: icon.midY)) }.map { (icon: icon, screen: $0) }
        }
        guard let screen = found?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let work = CGRect(x: visible.minX - frame.minX, y: frame.maxY - visible.maxY, width: visible.width, height: visible.height)
        let anchor = found.map { CGPoint(x: $0.icon.midX - frame.minX, y: frame.maxY - $0.icon.midY) } ?? CGPoint(x: frame.width, y: 0)
        return (screen, Tour.place(anchor: anchor, in: work))
    }

    /// `--preview-tour <folder>`: draws every step to tour-<n>-<step>.png, for checking the
    /// bubbles without watching the tour.
    static func writePreviews(to folder: URL, preferences: Preferences, steps: [TourStep], closeTitle: String = "Skip tour") async {
        let canvas = CGSize(width: 1100, height: 640)
        let spot = Tour.place(anchor: CGPoint(x: 900, y: 12), in: CGRect(x: 0, y: 30, width: 1100, height: 610))
        for number in steps.indices {
            let model = TourModel(
                steps: steps, spot: spot, canvas: canvas, closeTitle: closeTitle, look: Looks.current(preferences.settings.sushi)
            )
            for _ in 0..<number { model.next() }
            let scene = TourScene(model: model, preferences: preferences, time: model.flight.flyIn + 1)
                .background(Color(red: 0.16, green: 0.17, blue: 0.2))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: scene)
            window.alphaValue = 0
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))
            if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let file = folder.appending(path: "tour-\(number + 1)-\(steps[number].id).png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
                print(file.path)
            }
            window.orderOut(nil)
        }
    }
}
