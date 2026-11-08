import Foundation
import Testing

@testable import SushiBuddy

// The same cases as windows/test/whats-new.test.js, so both apps pick the same notes.

private let notes: WhatsNew.Notes = [
    "1.6": ["Tips!", "Versions!"],
    "1.5": ["The tour."],
    "1.4": [],
    "later": ["Not a version."],
]

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func version(_ text: String) throws -> Version {
    try #require(Version(text))
}

struct WhatsNewTests {
    @Test func picksTheInstalledVersionsOwnNotes() throws {
        let picked = try #require(WhatsNew.pick(notes, installed: version("1.6")))
        #expect(picked.version == Version("1.6"))
        #expect(picked.lines == ["Tips!", "Versions!"])
    }

    @Test func aVersionWithoutNotesGetsTheNewestOlderOnes() throws {
        #expect(try WhatsNew.pick(notes, installed: version("1.6.1"))?.version == Version("1.6"))
        #expect(try WhatsNew.pick(notes, installed: version("1.5.9"))?.version == Version("1.5"))
    }

    @Test func aPatchZeroCountsAsItsMinor() throws {
        #expect(try WhatsNew.pick(notes, installed: version("1.6.0"))?.version == Version("1.6"))
    }

    @Test func skipsEmptyListsAndKeysThatAreNotVersions() throws {
        #expect(try WhatsNew.pick(notes, installed: version("1.4.2")) == nil)
        #expect(try WhatsNew.pick(notes, installed: version("1.3")) == nil)
    }

    @Test func showsAVersionWithoutTrailingZeroParts() throws {
        #expect(try WhatsNew.display(version("1.5.0")) == "1.5")
        #expect(try WhatsNew.display(version("1.5")) == "1.5")
        #expect(try WhatsNew.display(version("1.4.1")) == "1.4.1")
        #expect(try WhatsNew.display(version("2.0.0")) == "2.0")
    }

    @Test func oneStepPerLineTheFirstNamingTheVersionTheLastLinkingTheReleaseNotes() throws {
        let steps = WhatsNew.steps(notes, installed: Version("1.6.0"))
        #expect(steps.map(\.text) == ["New in 1.6: Tips!", "Versions!"])
        #expect(steps.map(\.link) == [nil, WhatsNew.releaseNotes])
        #expect(Set(steps.map(\.id)).count == steps.count)
    }

    @Test func withoutNotesTheSushiPointsToTheReleaseNotes() throws {
        for installed in [Version("1.0"), nil] {
            let steps = WhatsNew.steps(notes, installed: installed)
            #expect(steps.count == 1)
            #expect(steps.first?.link == WhatsNew.releaseNotes)
        }
    }

    @Test func theBundledNotesAreVersionsWithLinesAndCoverTheAppsVersion() throws {
        let data = try Data(contentsOf: repository.appending(path: "Resources/whats-new.json"))
        let bundled = try #require(WhatsNew.decode(data))
        for (key, lines) in bundled {
            #expect(Version(key) != nil, "\(key) is not a version")
            #expect(!lines.isEmpty, "\(key) has no lines")
        }
        let plist = try Data(contentsOf: repository.appending(path: "mac/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        let version = try #require((info["CFBundleShortVersionString"] as? String).flatMap(Version.init))
        #expect(WhatsNew.pick(bundled, installed: version) != nil, "whats-new.json has nothing for \(version)")
    }
}
