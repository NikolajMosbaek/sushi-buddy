import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.nsscode.SushiBuddy", category: "usage")

/// The anonymous usage summary: once a day, only while Share anonymous usage statistics is on, the
/// app tells TelemetryDeck which settings you picked and how often the sushi flew, under a random ID
/// made when you turned it on (and forgotten when you turn it off), hashed before it leaves. Never a
/// line, a project or anything you typed. The same rules and fields as windows/usage.js.
enum Usage {
    static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")
    static let signal = "Sushi.dailySummary"
    static let triggers = ["menu", "shortcut", "script", "auto", "break", "welcomeBack", "pomodoro", "claudeDone", "claudeNeedsYou"]
    static let quietReasons = ["away", "focus", "call", "presenting"]

    /// TelemetryDeck's app ID, from Resources/usage.json. Empty sends nothing.
    static let appID: String = Bundle.main.url(forResource: "usage", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?["appID"] ?? ""

    struct Record: Codable, Equatable {
        var id: String
        var counts: [String: Int] = [:]
        var everChanged: [String] = []
        var lastSent: String?
    }

    /// A value in the summary: text, a count, or a yes or no.
    enum Value: Equatable, Encodable {
        case text(String)
        case number(Int)
        case flag(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .number(let number): try container.encode(number)
            case .flag(let flag): try container.encode(flag)
            }
        }
    }

    struct Environment {
        var version: String
        var build: String
        var operatingSystem: String
        var systemVersion: String
        var systemMajorVersion: String
        var architecture: String
        var isDebug: Bool
        var installSource: String
    }

    struct Signal: Encodable, Equatable {
        let appID: String
        let clientUser: String
        let type: String
        let isTestMode: Bool
        let payload: [String: Value]
    }

    static func hash(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// What started a flight: `via` when the caller knows (the shortcut, a script), else the occasion.
    static func trigger(_ occasion: String, automatic: Bool, via: String? = nil) -> String {
        if let via { return via }
        if occasion == "motivate" { return automatic ? "auto" : "menu" }
        if occasion.hasPrefix("pomodoro") { return "pomodoro" }
        return occasion
    }

    static func count(_ record: Record, _ key: String) -> Record {
        var record = record
        record.counts[key, default: 0] += 1
        return record
    }

    /// The settings that differ from their defaults; sharing itself is always on when anything is sent.
    static func changedKeys(_ settings: Settings, defaults: Settings = Settings()) -> [String] {
        let defaultValues = defaults.values
        return settings.values
            .filter { key, value in key != "shareUsage" && defaultValues[key].map { "\($0)" } != "\(value)" }
            .map(\.key)
            .sorted()
    }

    static func noteSettings(_ record: Record, _ settings: Settings, defaults: Settings = Settings()) -> Record {
        var record = record
        record.everChanged = Set(record.everChanged).union(changedKeys(settings, defaults: defaults)).sorted()
        return record
    }

    /// `date` as YYYY-MM-DD in local time: one summary per calendar day where you are.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isDue(_ record: Record, today: String) -> Bool {
        record.lastSent != today
    }

    /// The summary: the app and system under TelemetryDeck's own names (its charts read those), every
    /// setting as text, and a count for every trigger and quiet rule, zero included. Flat, as the API wants.
    static func payload(_ settings: Settings, _ record: Record, _ env: Environment, defaults: Settings = Settings()) -> [String: Value] {
        let counted = { (key: String) in Value.number(record.counts[key] ?? 0) }
        var summary: [String: Value] = [
            "TelemetryDeck.AppInfo.version": .text(env.version),
            "TelemetryDeck.AppInfo.buildNumber": .text(env.build),
            "TelemetryDeck.AppInfo.versionAndBuildNumber": .text("\(env.version) \(env.build)"),
            "TelemetryDeck.Device.operatingSystem": .text(env.operatingSystem),
            "TelemetryDeck.Device.platform": .text(env.operatingSystem),
            "TelemetryDeck.Device.systemVersion": .text(env.systemVersion),
            "TelemetryDeck.Device.systemMajorVersion": .text(env.systemMajorVersion),
            "TelemetryDeck.Device.architecture": .text(env.architecture),
            "TelemetryDeck.RunContext.isDebug": .flag(env.isDebug),
            "Sushi.Install.source": .text(env.installSource),
            "Sushi.Settings.changedCount": .number(changedKeys(settings, defaults: defaults).count),
            "Sushi.Settings.everChanged": .text(record.everChanged.isEmpty ? "none" : record.everChanged.joined(separator: ",")),
            "Sushi.Pets": counted("pet"),
            "Sushi.Health.unexpectedQuits": counted("unexpectedQuit"),
        ]
        for (key, value) in settings.values where key != "shareUsage" {
            summary["Sushi.Settings.\(key)"] = .text("\(value)")
        }
        for name in triggers { summary["Sushi.Flights.\(name)"] = counted("flight.\(name)") }
        for reason in quietReasons { summary["Sushi.Skips.\(reason)"] = counted("skip.\(reason)") }
        return summary
    }

    /// What goes to TelemetryDeck: one signal, with the ID hashed.
    static func body(appID: String, record: Record, payload: [String: Value], testMode: Bool) -> [Signal] {
        [Signal(appID: appID, clientUser: hash(record.id), type: signal, isTestMode: testMode, payload: payload)]
    }

    static func encode(_ body: [Signal], pretty: Bool) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys]
        return try? encoder.encode(body)
    }

    /// After a send: what was sent comes off the counts, so a flight during the request isn't lost.
    static func afterSend(_ record: Record, sent: Record, today: String) -> Record {
        var record = record
        record.counts = record.counts.reduce(into: [:]) { left, entry in
            let rest = entry.value - (sent.counts[entry.key] ?? 0)
            if rest > 0 { left[entry.key] = rest }
        }
        record.lastSent = today
        return record
    }

    /// Whether the last run ended without quitting, while the computer stayed on: it started at
    /// `runningSince` and the computer has been up since before then. A restart ends every app, so it
    /// doesn't count. All in seconds.
    static func quitUnexpectedly(runningSince: TimeInterval?, now: TimeInterval, uptime: TimeInterval) -> Bool {
        guard let runningSince else { return false }
        return uptime >= now - runningSince
    }
}

/// Keeps the usage summary: counts what happens while sharing is on, and sends it once a day.
@MainActor
final class UsageReporter {
    private let preferences: Preferences
    private var sending = false
    private var isRunning = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    private var settings: Settings { preferences.settings }

    /// At launch: a run that didn't quit counts as an unexpected quit, and this one starts.
    func launched() {
        let now = Date.now.timeIntervalSince1970
        sharingChanged()
        if Usage.quitUnexpectedly(runningSince: preferences.runningSince, now: now, uptime: ProcessInfo.processInfo.systemUptime) {
            count("unexpectedQuit")
        }
        preferences.runningSince = now
        isRunning = true
    }

    /// Only the run that started the app clears it, not a --preview run quitting next to it.
    func quitting() {
        guard isRunning else { return }
        preferences.runningSince = nil
    }

    /// Turning sharing on makes a new random ID; turning it off forgets the ID and every count.
    func sharingChanged() {
        if settings.shareUsage, preferences.usage == nil {
            preferences.usage = Usage.noteSettings(Usage.Record(id: UUID().uuidString), settings)
        } else if !settings.shareUsage, preferences.usage != nil {
            preferences.usage = nil
        }
    }

    func settingsChanged() {
        guard settings.shareUsage, let record = preferences.usage else { return }
        preferences.usage = Usage.noteSettings(record, settings)
    }

    /// Counts nothing while sharing is off.
    func count(_ key: String) {
        guard settings.shareUsage, let record = preferences.usage else { return }
        preferences.usage = Usage.count(record, key)
    }

    /// The request as it would go now, for Settings' Show What's Sent.
    func preview() -> String {
        let record = preferences.usage ?? Usage.Record(id: "a random ID, made when you turn sharing on")
        var settings = settings
        settings.shareUsage = true
        let body = Usage.body(appID: Usage.appID, record: record, payload: Usage.payload(settings, record, Self.environment), testMode: Self.isTestMode)
        return Usage.encode(body, pretty: true).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Every few seconds: when sharing is on and today's summary hasn't gone, send it.
    func tick() {
        let today = Usage.day(.now)
        guard settings.shareUsage, !Usage.appID.isEmpty, !sending, let endpoint = Usage.endpoint,
              let record = preferences.usage, Usage.isDue(record, today: today) else { return }
        let body = Usage.body(appID: Usage.appID, record: record, payload: Usage.payload(settings, record, Self.environment), testMode: Self.isTestMode)
        guard let data = Usage.encode(body, pretty: false) else { return }
        sending = true
        Task { [weak self] in
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let status = (try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse
            guard let self else { return }
            self.sending = false
            guard status?.statusCode == 200 else {
                logger.notice("usage summary not sent (\(status?.statusCode ?? 0, privacy: .public)); trying again later")
                return
            }
            // Sharing may have gone off while the request was out; then there's nothing left to update.
            if let current = self.preferences.usage, current.id == record.id {
                self.preferences.usage = Usage.afterSend(current, sent: record, today: today)
            }
        }
    }

    #if DEBUG
    static let isTestMode = true
    #else
    static let isTestMode = false
    #endif

    static var environment: Usage.Environment {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let info = Bundle.main.infoDictionary
        return Usage.Environment(
            version: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            operatingSystem: "macOS",
            systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            systemMajorVersion: "\(os.majorVersion)",
            // The Mac app is built for Apple silicon only.
            architecture: "arm64",
            isDebug: isTestMode,
            installSource: FileManager.default.fileExists(atPath: "/opt/homebrew/Caskroom/sushi-buddy") ? "homebrew" : "download"
        )
    }
}
