import AppKit
import Observation
import OSLog

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "sushi")

/// Decides when the sushi flies and what it says, and keeps the parts that make it fly on
/// their own (Auto-motivate, break reminders, welcome back, Pomodoro, the shortcut, the
/// Claude Code listener) in step with Settings.
///
/// A flight you ask for (the menu, the shortcut, a Pomodoro you started, a script's /fly)
/// always goes. An automatic one holds off while a quiet rule holds, and the skip is shown
/// in Settings so a quiet Auto-motivate doesn't look broken.
@MainActor
@Observable
final class Sushi {
    struct Skip: Equatable {
        let occasion: String
        let reason: QuietReason
        let at: Date
    }

    let preferences: Preferences
    @ObservationIgnored let updates: Updates
    @ObservationIgnored let flights = FlightController()
    @ObservationIgnored let tour = TourController()

    private(set) var lastSkip: Skip?
    private(set) var linesProblem: String?
    private(set) var hotkeyProblem: String?
    private(set) var listenerProblem: String?
    private(set) var claudeLastHeard: Date?
    private(set) var pomodoro: Pomodoro?

    @ObservationIgnored private var autoMotivate: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var pomodoroTimer: Task<Void, Never>?
    @ObservationIgnored private var presence = Presence()
    @ObservationIgnored private var breaks = BreakTimer(activeSince: .now)
    @ObservationIgnored private var claude = ClaudeTracker()
    @ObservationIgnored private var timekeeping: NSObjectProtocol?
    @ObservationIgnored private var tourWaiting = false
    @ObservationIgnored private lazy var hotkey = Hotkey { [weak self] in self?.fly("motivate") }
    @ObservationIgnored private lazy var listener: Listener = {
        let listener = Listener(
            version: Updates.installedVersion,
            onClaude: { [weak self] event in self?.heard(event) },
            onFly: { [weak self] message in self?.fly("motivate", message: message) }
        )
        listener.onProblemChange = { [weak self] problem in self?.listenerProblem = problem }
        return listener
    }()

    init(preferences: Preferences, updates: Updates) {
        self.preferences = preferences
        self.updates = updates
    }

    var settings: Settings { preferences.settings }

    func start() {
        apply(since: nil)
        preferences.onChange = { [weak self] old in self?.apply(since: old) }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.watch()
            }
        }
        // The tour, once, a moment after launch so the menu bar icon is in place to fly to.
        tourWaiting = !preferences.tourSeen
        if tourWaiting {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.startTourIfQuiet()
            }
        }
    }

    // MARK: Tour

    /// Shows the tour now, as Settings and --tour do. It counts as seen only once it shows: while
    /// What's New holds the bubble, the tour that starts on its own keeps waiting.
    func startTour() {
        let shortcut = Hotkey.presets.first { $0.id == settings.hotkey && $0.id != "off" }?.label
        guard tour.start(steps: Tour.steps(on: .mac, shortcut: shortcut), preferences: preferences) else { return }
        tourWaiting = false
        preferences.tourSeen = true
    }

    /// What's new in this version, in the tour's bubble, as the menu and Settings ask for it.
    func showWhatsNew() {
        let steps = WhatsNew.steps(WhatsNew.bundled, installed: Version(Updates.installedVersion))
        tour.start(steps: steps, preferences: preferences, closeTitle: "Close")
    }

    /// The tour that starts on its own waits, like an automatic flight, while a quiet rule holds.
    private func startTourIfQuiet() {
        guard tourWaiting else { return }
        let quiet = Quiet.reason(settings, SystemSignals.quietSignals(awayMinutes: settings.awayMinutes))
        if Tour.startsOnItsOwn(seen: preferences.tourSeen, quiet: quiet) { startTour() }
    }

    /// Applies what changed in Settings (everything, at launch).
    private func apply(since old: Settings?) {
        let new = settings
        if old?.autoMotivateSeconds != new.autoMotivateSeconds { restartAutoMotivate() }
        if old?.breakReminderMinutes != new.breakReminderMinutes { breaks = BreakTimer(activeSince: .now) }
        if old?.hotkey != new.hotkey { hotkeyProblem = hotkey.register(new.hotkey) }
        if old?.listen != new.listen {
            if new.listen { listener.start() } else { listener.stop() }
        }
        if old?.checkForUpdates != new.checkForUpdates { updates.setAutomaticChecks(new.checkForUpdates) }
        let automatic = new.autoMotivateSeconds > 0 || new.breakReminderMinutes > 0 || new.welcomeBack
        if automatic, new.quietDuringFocus, FocusStatus.authorization == .notDetermined {
            Task { _ = await FocusStatus.requestAccess() }
        }
        updateTimekeeping()
    }

    /// macOS naps an app with no windows, which can hold its timers back by minutes. While
    /// something runs on a clock, keep the app awake; the Mac itself can still sleep.
    private func updateTimekeeping() {
        let onAClock = settings.autoMotivateSeconds > 0 || settings.breakReminderMinutes > 0 || settings.welcomeBack || pomodoro != nil
        if onAClock, timekeeping == nil {
            timekeeping = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Timing automatic flights"
            )
        } else if !onAClock, let activity = timekeeping {
            ProcessInfo.processInfo.endActivity(activity)
            timekeeping = nil
        }
    }

    // MARK: Flying

    /// Flies now. `occasion` is "motivate" or one of the line file's occasions; an automatic
    /// flight first checks the quiet rules.
    func fly(_ occasion: String, automatic: Bool = false, project: String? = nil, message: String? = nil) {
        if tour.isRunning {
            tour.react()
            return
        }
        if automatic, let reason = Quiet.reason(settings, SystemSignals.quietSignals(awayMinutes: settings.awayMinutes)) {
            lastSkip = Skip(occasion: occasion, reason: reason, at: .now)
            logger.notice("skipped \(occasion, privacy: .public): \(reason.explanation, privacy: .public)")
            return
        }
        guard let screen = flights.currentScreen else {
            logger.error("no screen to fly on")
            return
        }
        let text = message ?? line(for: occasion, project: project)
        let flight = Flight.random(on: screen.frame.size, message: text, path: .named(settings.flightPath), look: Looks.current(settings.sushi))
        flights.launch(flight, on: screen, petting: settings.petting, sound: settings.sound)
    }

    private func line(for occasion: String, project: String?) -> String {
        var streak: (days: Int, firstToday: Bool)?
        if occasion == "motivate" {
            let advanced = Streak.advance(preferences.streak, to: .now)
            preferences.streak = advanced.streak
            if settings.streaks { streak = (advanced.streak.days, advanced.firstToday) }
        }
        let moment = Lines.Moment(date: .now, contextLines: settings.contextLines, streak: streak, project: project)
        return Lines.pick(occasion, from: loadLines(), at: moment)
    }

    // MARK: Lines

    static let bundledLines: Lines.Book = Bundle.main.url(forResource: "lines", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(Lines.decode) ?? ["anytime": [Lines.fallback]]

    static let userLinesURL = URL.applicationSupportDirectory.appending(path: "Sushi Buddy/lines.json")

    var hasOwnLines: Bool { FileManager.default.fileExists(atPath: Self.userLinesURL.path) }

    /// The built-in lines with yours on top, read fresh so an edit counts from the next flight.
    @discardableResult
    func loadLines() -> Lines.Book {
        let merged = Lines.merge(bundled: Self.bundledLines, user: try? Data(contentsOf: Self.userLinesURL))
        linesProblem = merged.error
        return merged.lines
    }

    /// Opens your lines.json, first made as a copy of the built-in one.
    func editLines() {
        let url = Self.userLinesURL
        if !hasOwnLines, let bundled = Bundle.main.url(forResource: "lines", withExtension: "json") {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: bundled, to: url)
        }
        NSWorkspace.shared.open(url)
    }

    func revealLines() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.userLinesURL])
    }

    /// Moves your lines.json to the Trash, back to the built-in lines.
    func resetLines() {
        try? FileManager.default.trashItem(at: Self.userLinesURL, resultingItemURL: nil)
        loadLines()
    }

    // MARK: Tip jar

    static let tipJar = "https://ko-fi.com/nikolajsim"

    /// Opens the tip jar in the browser. A tip is a thank-you; it unlocks nothing.
    func openTipJar() {
        if let url = URL(string: Self.tipJar) { NSWorkspace.shared.open(url) }
    }

    // MARK: On their own

    private func restartAutoMotivate() {
        autoMotivate?.cancel()
        let interval = settings.autoMotivateSeconds
        guard interval > 0 else {
            autoMotivate = nil
            return
        }
        // Counted from now, so a change takes effect at once. A turn during a quiet time is skipped, not saved.
        autoMotivate = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                self?.fly("motivate", automatic: true)
            }
        }
    }

    /// Every few seconds: have you come back, and is a break due?
    private func watch() {
        startTourIfQuiet()
        let now = Date.now
        let idle = SystemSignals.idleSeconds
        let away = Quiet.isAway(idleSeconds: idle, locked: SystemSignals.isLocked, awayMinutes: settings.awayMinutes)
        let back = presence.tick(now: now, away: away, idleSeconds: idle)
        if back.cameBack, settings.welcomeBack, back.awayFor >= TimeInterval(settings.awayMinutes * 60) {
            fly("welcomeBack", automatic: true)
        }
        if breaks.tick(now: now, idleSeconds: idle, intervalMinutes: settings.breakReminderMinutes) {
            fly("break", automatic: true)
        }
    }

    // MARK: Pomodoro

    func startPomodoro() {
        pomodoro = Pomodoro.start(at: .now, settings)
        schedulePomodoro()
        updateTimekeeping()
    }

    func stopPomodoro() {
        pomodoroTimer?.cancel()
        pomodoroTimer = nil
        pomodoro = nil
        updateTimekeeping()
    }

    private func schedulePomodoro() {
        pomodoroTimer?.cancel()
        guard let current = pomodoro else { return }
        pomodoroTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, current.endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            let next = current.next(at: .now, self.settings)
            self.pomodoro = next.pomodoro
            self.fly(next.line)
            self.schedulePomodoro()
        }
    }

    // MARK: Claude Code

    private func heard(_ event: ClaudeEvent) {
        claudeLastHeard = .now
        logger.notice("Claude Code: \(event.hookEventName ?? "?", privacy: .public)")
        if let cheer = claude.handle(event, at: .now, settings) {
            fly(cheer.kind, automatic: true, project: cheer.project)
        }
    }
}
