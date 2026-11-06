import Intents

/// Whether a macOS Focus (Do Not Disturb, Work, …) is on, so Auto-motivate can hold off.
/// "Motivate me" is the person asking, so it flies regardless.
@MainActor
enum FocusStatus {
    static var isFocused: Bool {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused ?? false
    }

    static var authorization: INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    /// Asks once; macOS remembers the answer and only shows the prompt while it is undecided.
    static func requestAccess() async -> INFocusStatusAuthorizationStatus {
        await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
