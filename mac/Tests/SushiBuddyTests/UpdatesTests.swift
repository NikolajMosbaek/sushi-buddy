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
