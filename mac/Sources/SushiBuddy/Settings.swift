import Foundation
import Observation

/// Every choice in Settings, with the same names, choices and defaults as windows/settings.js.
///
/// Defaults: whatever flies or makes a sound on its own starts off; whatever only holds
/// automatic flights back starts on; looks (paths, petting, lines) start on.
struct Settings: Equatable, Sendable {
    var autoMotivateSeconds = 0
    var breakReminderMinutes = 0
    var welcomeBack = false
    var awayMinutes = 10
    var quietDuringFocus = true
    var quietOnCalls = true
    var quietWhenPresenting = true
    var quietWhenAway = true
    var flightPath = "random"
    var petting = true
    var sound = "off"
    var hotkey = "control+option+command+s"
    var contextLines = true
    var streaks = true
    var listen = true
    var claudeDone = true
    var claudeMinMinutes = 2
    var claudeNeedsYou = true
    var pomodoroFocusMinutes = 25
    var pomodoroBreakMinutes = 5
    var pomodoroLongBreaks = true
    var checkForUpdates = true

    enum Choices {
        static let autoMotivateSeconds = [0, 900, 1800, 3600, 7200, 14400]
        static let breakReminderMinutes = [0, 30, 45, 60, 90]
        static let awayMinutes = [5, 10, 15, 30]
        static let flightPath = ["random", "classic", "loop", "bounce", "zigzag"]
        static let sound = ["off", "chime", "whirr"]
        static let hotkey = ["off", "control+option+command+s", "control+option+s", "control+option+command+m"]
        static let claudeMinMinutes = [0, 1, 2, 5, 10]
        static let pomodoroFocusMinutes = [15, 25, 45, 50]
        static let pomodoroBreakMinutes = [5, 10]
    }

    init() {}

    /// Each setting from `values`, keeping the default where one is missing or not among its choices.
    init(values: [String: Any]) {
        let defaults = Settings()
        func int(_ key: String, _ choices: [Int], _ fallback: Int) -> Int {
            guard let value = values[key] as? Int, choices.contains(value) else { return fallback }
            return value
        }
        func text(_ key: String, _ choices: [String], _ fallback: String) -> String {
            guard let value = values[key] as? String, choices.contains(value) else { return fallback }
            return value
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            values[key] as? Bool ?? fallback
        }
        autoMotivateSeconds = int("autoMotivateSeconds", Choices.autoMotivateSeconds, defaults.autoMotivateSeconds)
        breakReminderMinutes = int("breakReminderMinutes", Choices.breakReminderMinutes, defaults.breakReminderMinutes)
        welcomeBack = flag("welcomeBack", defaults.welcomeBack)
        awayMinutes = int("awayMinutes", Choices.awayMinutes, defaults.awayMinutes)
        quietDuringFocus = flag("quietDuringFocus", defaults.quietDuringFocus)
        quietOnCalls = flag("quietOnCalls", defaults.quietOnCalls)
        quietWhenPresenting = flag("quietWhenPresenting", defaults.quietWhenPresenting)
        quietWhenAway = flag("quietWhenAway", defaults.quietWhenAway)
        flightPath = text("flightPath", Choices.flightPath, defaults.flightPath)
        petting = flag("petting", defaults.petting)
        sound = text("sound", Choices.sound, defaults.sound)
        hotkey = text("hotkey", Choices.hotkey, defaults.hotkey)
        contextLines = flag("contextLines", defaults.contextLines)
        streaks = flag("streaks", defaults.streaks)
        listen = flag("listen", defaults.listen)
        claudeDone = flag("claudeDone", defaults.claudeDone)
        claudeMinMinutes = int("claudeMinMinutes", Choices.claudeMinMinutes, defaults.claudeMinMinutes)
        claudeNeedsYou = flag("claudeNeedsYou", defaults.claudeNeedsYou)
        pomodoroFocusMinutes = int("pomodoroFocusMinutes", Choices.pomodoroFocusMinutes, defaults.pomodoroFocusMinutes)
        pomodoroBreakMinutes = int("pomodoroBreakMinutes", Choices.pomodoroBreakMinutes, defaults.pomodoroBreakMinutes)
        pomodoroLongBreaks = flag("pomodoroLongBreaks", defaults.pomodoroLongBreaks)
        checkForUpdates = flag("checkForUpdates", defaults.checkForUpdates)
    }

    /// Every setting by its key, as stored.
    var values: [String: Any] {
        [
            "autoMotivateSeconds": autoMotivateSeconds,
            "breakReminderMinutes": breakReminderMinutes,
            "welcomeBack": welcomeBack,
            "awayMinutes": awayMinutes,
            "quietDuringFocus": quietDuringFocus,
            "quietOnCalls": quietOnCalls,
            "quietWhenPresenting": quietWhenPresenting,
            "quietWhenAway": quietWhenAway,
            "flightPath": flightPath,
            "petting": petting,
            "sound": sound,
            "hotkey": hotkey,
            "contextLines": contextLines,
            "streaks": streaks,
            "listen": listen,
            "claudeDone": claudeDone,
            "claudeMinMinutes": claudeMinMinutes,
            "claudeNeedsYou": claudeNeedsYou,
            "pomodoroFocusMinutes": pomodoroFocusMinutes,
            "pomodoroBreakMinutes": pomodoroBreakMinutes,
            "pomodoroLongBreaks": pomodoroLongBreaks,
            "checkForUpdates": checkForUpdates,
        ]
    }
}

/// The settings as the app keeps them, in its user defaults (`defaults read com.nsscode.SushiBuddy`).
/// A change is stored at once and handed to `onChange`, which applies it.
@MainActor
@Observable
final class Preferences {
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            for (key, value) in settings.values { defaults.set(value, forKey: key) }
            onChange?(oldValue)
        }
    }

    @ObservationIgnored var onChange: ((Settings) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Settings(values: defaults.dictionaryRepresentation())
    }

    /// The days in a row with a motivation; bookkeeping, not a setting.
    var streak: Streak? {
        get { defaults.data(forKey: "streak").flatMap { try? JSONDecoder().decode(Streak.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "streak") }
    }

    /// Whether the tour has started once; bookkeeping, not a setting.
    var tourSeen: Bool {
        get { defaults.bool(forKey: "tourSeen") }
        set { defaults.set(newValue, forKey: "tourSeen") }
    }
}
