import AppKit
import Observation
import Sparkle

/// A dotted version (`1.2.0`, or a tag `v1.2.0`), compared part by part with missing parts as 0.
struct Version: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ text: String) {
        let bare = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap(\.self)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func == (lhs: Version, rhs: Version) -> Bool { compare(lhs, rhs) == 0 }
    static func < (lhs: Version, rhs: Version) -> Bool { compare(lhs, rhs) < 0 }

    private static func compare(_ lhs: Version, _ rhs: Version) -> Int {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// Keeps Sushi Buddy up to date with Sparkle. At launch and once a day (unless switched off in
/// Settings) it reads the appcast on this repo's latest GitHub release; it checks a download's
/// EdDSA signature and Developer ID before it swaps the app. With Install updates automatically it
/// downloads in the background and installs when Sushi Buddy quits.
///
/// A menu bar app is never in front, so an update a daily check finds doesn't pop up a window
/// behind everything: the menu's Check for Updates… turns into "Update to …" until it's looked at.
@MainActor
@Observable
final class Updates: NSObject {
    static let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// The version a daily check found that nobody has looked at yet.
    private(set) var waiting: String?

    /// Settings → Install updates automatically. Sparkle keeps it in the app's defaults.
    var installsAutomatically = false {
        didSet {
            if installsAutomatically != oldValue { controller.updater.automaticallyDownloadsUpdates = installsAutomatically }
        }
    }

    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self
    )

    override init() {
        super.init()
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
    }

    /// Only on a normal launch: the command-line flags that print or draw and quit stay offline.
    func start() {
        controller.startUpdater()
    }

    func setAutomaticChecks(_ on: Bool) {
        controller.updater.automaticallyChecksForUpdates = on
    }

    /// Check for Updates… and Update to …: Sparkle's window, which says what it found.
    func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

// Sparkle calls these on the main thread.
extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { waiting = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waiting = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        waiting = nil
    }
}
