import Foundation

/// What's new in a version, for the menu's What's New: the highlights in whats-new.json, said
/// by the sushi one at a time in the tour's bubble. The same rules as windows/whats-new.js.
enum WhatsNew {
    typealias Notes = [String: [String]]

    static let releaseNotes = URL(string: "https://github.com/NikolajMosbaek/sushi-buddy/releases")

    static let bundled: Notes = Bundle.main.url(forResource: "whats-new", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(decode) ?? [:]

    /// The installed version as the menu and Settings show it.
    @MainActor static var installed: String {
        Version(Updates.installedVersion).map(display) ?? Updates.installedVersion
    }

    static func decode(_ data: Data) -> Notes? {
        try? JSONDecoder().decode(Notes.self, from: data)
    }

    /// The notes for `installed`: its own, or, for a version without any (a patch), the newest older ones.
    static func pick(_ notes: Notes, installed: Version) -> (version: Version, lines: [String])? {
        notes
            .compactMap { key, lines in Version(key).map { (version: $0, lines: lines) } }
            .filter { $0.version <= installed && !$0.lines.isEmpty }
            .max { $0.version < $1.version }
    }

    /// `1.5.0` as 1.5: trailing zero parts dropped, down to major.minor.
    static func display(_ version: Version) -> String {
        var parts = version.parts
        while parts.count > 2, parts.last == 0 { parts.removeLast() }
        return parts.map(String.init).joined(separator: ".")
    }

    /// The bubble's steps: one per line, the last linking all the release notes, and then, until the
    /// sushi has asked once, the step that asks to share usage statistics.
    static func steps(_ notes: Notes, installed: Version?, asksToShare: Bool = false) -> [TourStep] {
        let lines: [TourStep]
        if let installed, let picked = pick(notes, installed: installed) {
            let name = display(picked.version)
            lines = picked.lines.enumerated().map { index, line in
                TourStep(
                    id: "new-\(index + 1)",
                    text: index == 0 ? "New in \(name): \(line)" : line,
                    link: index == picked.lines.count - 1 ? releaseNotes : nil
                )
            }
        } else {
            lines = [TourStep(id: "none", text: "I don't have notes for this version. All my release notes are on GitHub.", link: releaseNotes)]
        }
        return asksToShare ? lines + [Tour.share] : lines
    }
}
