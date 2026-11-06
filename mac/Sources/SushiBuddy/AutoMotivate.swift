import Foundation

/// Flies on its own every so often. The interval is stored in seconds (0 = off),
/// so the Windows app's presets and this one's read the same.
@MainActor
final class AutoMotivate {
    static let defaultsKey = "autoMotivateSeconds"

    static let presets: [(label: String, seconds: Int)] = [
        ("Off", 0),
        ("Every 15 minutes", 15 * 60),
        ("Every 30 minutes", 30 * 60),
        ("Every hour", 60 * 60),
        ("Every 2 hours", 2 * 60 * 60),
        ("Every 4 hours", 4 * 60 * 60),
    ]

    private let fly: @MainActor () -> Void
    private var timer: Task<Void, Never>?

    init(fly: @escaping @MainActor () -> Void) {
        self.fly = fly
    }

    var seconds: Int {
        UserDefaults.standard.integer(forKey: Self.defaultsKey)
    }

    func set(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Self.defaultsKey)
        start()
    }

    /// (Re)starts the countdown from now, so a change takes effect at once.
    func start() {
        timer?.cancel()
        let interval = seconds
        guard interval > 0 else {
            timer = nil
            return
        }
        timer = Task { [fly] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                fly()
            }
        }
    }
}
