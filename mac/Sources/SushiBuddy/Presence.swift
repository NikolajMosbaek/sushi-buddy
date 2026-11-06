import Foundation

/// When automatic flights hold off, when you've come back, and when a break is due.
/// The same rules as windows/presence.js.
enum QuietReason: String, Sendable {
    case away, focus, call, presenting

    var explanation: String {
        switch self {
        case .away: "you were away"
        case .focus: "a Focus was on"
        case .call: "you were on a call"
        case .presenting: "you were presenting"
        }
    }
}

struct QuietSignals: Equatable, Sendable {
    var away = false
    var focus = false
    var call = false
    var presenting = false
}

enum Quiet {
    /// The first reason that holds and is switched on, or nil when an automatic flight may go.
    static func reason(_ settings: Settings, _ signals: QuietSignals) -> QuietReason? {
        if settings.quietWhenAway && signals.away { return .away }
        if settings.quietDuringFocus && signals.focus { return .focus }
        if settings.quietOnCalls && signals.call { return .call }
        if settings.quietWhenPresenting && signals.presenting { return .presenting }
        return nil
    }

    static func isAway(idleSeconds: TimeInterval, locked: Bool, awayMinutes: Int) -> Bool {
        locked || idleSeconds >= TimeInterval(awayMinutes * 60)
    }
}

/// Notices the step from away to back.
struct Presence: Equatable, Sendable {
    var awaySince: Date?

    /// True on the tick you come back.
    mutating func tick(now: Date, away: Bool, idleSeconds: TimeInterval) -> (cameBack: Bool, awayFor: TimeInterval) {
        if away {
            if awaySince == nil { awaySince = now.addingTimeInterval(-idleSeconds) }
            return (false, 0)
        }
        guard let since = awaySince else { return (false, 0) }
        awaySince = nil
        return (true, now.timeIntervalSince(since))
    }
}

/// Counts time at the computer since the last break; a reminder starts the count again.
struct BreakTimer: Equatable, Sendable {
    /// Five minutes without touching anything counts as a break.
    static let breakSeconds: TimeInterval = 5 * 60

    var activeSince: Date

    mutating func tick(now: Date, idleSeconds: TimeInterval, intervalMinutes: Int) -> Bool {
        if idleSeconds >= Self.breakSeconds {
            activeSince = now
            return false
        }
        if intervalMinutes > 0, now.timeIntervalSince(activeSince) >= TimeInterval(intervalMinutes * 60) {
            activeSince = now
            return true
        }
        return false
    }
}
