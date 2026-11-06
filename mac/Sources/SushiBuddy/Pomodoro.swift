import Foundation

/// Focus, break, focus, …; every fourth break long (15 minutes) when long breaks are on.
/// The same rules as windows/pomodoro.js.
struct Pomodoro: Equatable, Sendable {
    enum Phase: String, Sendable { case focus, shortBreak = "break", longBreak }

    static let longBreakMinutes = 15

    var phase: Phase
    var endsAt: Date
    var completed: Int

    static func start(at now: Date, _ settings: Settings) -> Pomodoro {
        Pomodoro(phase: .focus, endsAt: now.addingTimeInterval(minutes(settings.pomodoroFocusMinutes)), completed: 0)
    }

    /// The phase after this one, and the occasion the sushi announces it with.
    func next(at now: Date, _ settings: Settings) -> (pomodoro: Pomodoro, line: String) {
        if phase == .focus {
            let completed = completed + 1
            let long = settings.pomodoroLongBreaks && completed % 4 == 0
            let length = long ? Self.longBreakMinutes : settings.pomodoroBreakMinutes
            return (
                Pomodoro(phase: long ? .longBreak : .shortBreak, endsAt: now.addingTimeInterval(Self.minutes(length)), completed: completed),
                "pomodoroDone"
            )
        }
        return (
            Pomodoro(phase: .focus, endsAt: now.addingTimeInterval(Self.minutes(settings.pomodoroFocusMinutes)), completed: completed),
            "pomodoroBreakOver"
        )
    }

    /// "Focus, 12 min left", for the menu.
    func describe(at now: Date) -> String {
        let minutes = max(1, Int((endsAt.timeIntervalSince(now) / 60).rounded(.up)))
        let name = switch phase {
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
        return "\(name), \(minutes) min left"
    }

    private static func minutes(_ count: Int) -> TimeInterval { TimeInterval(count * 60) }
}
