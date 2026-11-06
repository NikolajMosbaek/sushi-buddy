import Foundation
import Testing

@testable import SushiBuddy

struct VersionTests {
    @Test func readsATagWithOrWithoutTheV() throws {
        #expect(try #require(Version("v1.2.0")).description == "1.2.0")
        #expect(try #require(Version("1.1")).description == "1.1")
    }

    @Test func refusesWhatIsNotAVersion() {
        #expect(Version("latest") == nil)
        #expect(Version("1.x") == nil)
        #expect(Version("") == nil)
    }

    @Test func comparesPartByPartAsNumbers() throws {
        #expect(try #require(Version("1.10")) > #require(Version("1.9")))
        #expect(try #require(Version("2.0")) > #require(Version("1.99.9")))
    }

    @Test func treatsMissingPartsAsZero() throws {
        #expect(try #require(Version("1.1")) == #require(Version("1.1.0")))
        #expect(try !(#require(Version("1.1")) < #require(Version("1.1.0"))))
    }
}

struct ReleaseTests {
    private let json = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/NikolajMosbaek/sushi-buddy/releases/tag/v1.2.0",
          "assets": [
            {"name": "Sushi-Buddy-windows-x64.zip",
             "browser_download_url": "https://example.com/Sushi-Buddy-windows-x64.zip"},
            {"name": "Sushi-Buddy-macOS-arm64.zip",
             "browser_download_url": "https://example.com/Sushi-Buddy-macOS-arm64.zip"}
          ]
        }
        """

    @Test func decodesGitHubsLatestRelease() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))

        #expect(release.version?.description == "1.2.0")
        #expect(release.macDownload.lastPathComponent == "Sushi-Buddy-macOS-arm64.zip")
    }

    @Test func fallsBackToTheReleasePageWithoutAMacDownload() throws {
        let page = try #require(URL(string: "https://github.com/NikolajMosbaek/sushi-buddy/releases/tag/v1.2.0"))
        let release = Release(tagName: "v1.2.0", htmlURL: page, assets: [])

        #expect(release.macDownload == page)
    }

    @Test func aNewerReleaseIsAnUpdate() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))

        #expect(UpdateOutcome(latest: release, current: Version("1.1")) == .available(release))
    }

    @Test func theSameOrAnOlderReleaseIsNot() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))

        #expect(UpdateOutcome(latest: release, current: Version("1.2")) == .upToDate)
        #expect(UpdateOutcome(latest: release, current: Version("1.3.1")) == .upToDate)
    }
}
