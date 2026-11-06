import AppKit
import Observation

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

/// GitHub's answer for the repo's latest release, the fields the check reads.
struct Release: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var version: Version? { Version(tagName) }

    /// The Mac zip, or the release page when the release has none.
    var macDownload: URL {
        assets.first { $0.name.localizedCaseInsensitiveContains("macos") }?.browserDownloadURL ?? htmlURL
    }
}

enum UpdateOutcome: Equatable, Sendable {
    case upToDate
    case available(Release)
    case failed(String)

    init(latest: Release, current: Version?) {
        guard let latestVersion = latest.version, let current, latestVersion > current else {
            self = .upToDate
            return
        }
        self = .available(latest)
    }
}

/// Checks GitHub for a newer release: quietly at launch and once a day, where a find
/// turns the menu's item into "Update to …", and on demand from the menu, which says
/// what it found. The download opens in the browser; nothing installs by itself.
@MainActor
@Observable
final class Updates {
    static let repository = "NikolajMosbaek/sushi-buddy"

    private(set) var available: Release?
    let current = Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")

    @ObservationIgnored private var quietChecks: Task<Void, Never>?

    func check() async -> UpdateOutcome {
        do {
            let outcome = UpdateOutcome(latest: try await latestRelease(), current: current)
            if case .available(let release) = outcome {
                available = release
            } else {
                available = nil
            }
            return outcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func startQuietChecks() {
        quietChecks?.cancel()
        quietChecks = Task {
            while !Task.isCancelled {
                _ = await check()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    func checkAndTell() async {
        let outcome = await check()
        NSApp.activate()
        let alert = NSAlert()
        switch outcome {
        case .upToDate:
            alert.messageText = "Sushi Buddy is up to date"
            alert.informativeText = "\(current?.description ?? "This") is the latest version."
        case .available(let release):
            alert.messageText = "Sushi Buddy \(release.version?.description ?? release.tagName) is available"
            alert.informativeText = "You have \(current?.description ?? "an older version"). The download opens in your browser."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { download(release) }
            return
        case .failed(let reason):
            alert.alertStyle = .warning
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = reason
        }
        alert.runModal()
    }

    func download(_ release: Release) {
        NSWorkspace.shared.open(release.macDownload)
    }

    private func latestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
