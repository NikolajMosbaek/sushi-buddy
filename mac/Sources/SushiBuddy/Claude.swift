import Foundation

/// The fields of a Claude Code hook event that matter here.
struct ClaudeEvent: Decodable, Sendable {
    var hookEventName: String?
    var sessionID: String?
    var cwd: String?
    var notificationType: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case notificationType = "notification_type"
        case message
    }
}

/// Turns Claude Code hook events into flights. The same rules as windows/claude.js.
///
/// The hooks (claude-code/ in this repo) post every UserPromptSubmit, Stop and permission
/// Notification here. A turn is timed from its prompt to its Stop, per session, so only
/// the long ones are cheered.
struct ClaudeTracker: Sendable {
    private var started: [String: Date] = [:]
    private(set) var lastHeard: Date?

    static func projectName(_ cwd: String?) -> String {
        (cwd ?? "").split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    }

    /// The occasion this event calls for ("claudeDone" or "claudeNeedsYou") and its project, or nil.
    mutating func handle(_ event: ClaudeEvent, at now: Date, _ settings: Settings) -> (kind: String, project: String)? {
        lastHeard = now
        started = started.filter { now.timeIntervalSince($0.value) <= 24 * 60 * 60 }

        let session = event.sessionID ?? ""
        let project = Self.projectName(event.cwd)
        switch event.hookEventName {
        case "UserPromptSubmit":
            started[session] = now
            return nil
        case "Stop":
            let start = started.removeValue(forKey: session)
            guard settings.claudeDone else { return nil }
            let long = start.map { now.timeIntervalSince($0) >= TimeInterval(settings.claudeMinMinutes * 60) }
                ?? (settings.claudeMinMinutes == 0)
            return long ? ("claudeDone", project) : nil
        case "Notification":
            guard settings.claudeNeedsYou else { return nil }
            let asking = event.notificationType == "permission_prompt"
                || (event.notificationType == nil && (event.message ?? "").localizedCaseInsensitiveContains("permission"))
            return asking ? ("claudeNeedsYou", project) : nil
        default:
            return nil
        }
    }
}
