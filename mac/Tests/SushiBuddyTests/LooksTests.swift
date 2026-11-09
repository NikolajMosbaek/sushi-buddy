import Foundation
import Testing

@testable import SushiBuddy

// The same cases as windows/test/looks.test.js, so both apps fly the same sushi on the same day.

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func on(_ year: Int, _ month: Int, _ day: Int) -> String {
    Looks.seasonal(year: year, month: month, day: day)
}

struct LooksTests {
    @Test func easterSundayFollowsTheChurchCalendar() {
        let known = [(2008, 3, 23), (2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2038, 4, 25), (2285, 3, 22)]
        for (year, month, day) in known {
            let easter = Looks.easterSunday(year)
            #expect(easter.month == month && easter.day == day, "Easter \(year)")
        }
    }

    @Test func jDagIsTheFirstFridayOfNovember() {
        #expect(Looks.firstFridayOfNovember(2024) == 1)
        #expect(Looks.firstFridayOfNovember(2025) == 7)
        #expect(Looks.firstFridayOfNovember(2026) == 6)
        #expect(Looks.firstFridayOfNovember(2027) == 5)
    }

    @Test func theCalendarPicksEachSeasonsSushiFromItsFirstDayToItsLast() {
        #expect(on(2026, 8, 31) == "classic")
        #expect(on(2026, 9, 1) == "rainy")
        #expect(on(2026, 9, 30) == "rainy")
        #expect(on(2026, 10, 1) == "classic")
        #expect(on(2026, 11, 5) == "classic")
        #expect(on(2026, 11, 6) == "jday")
        #expect(on(2026, 11, 30) == "jday")
        #expect(on(2026, 12, 1) == "santa")
        #expect(on(2026, 12, 26) == "santa")
        #expect(on(2026, 12, 27) == "classic")
        #expect(on(2027, 1, 1) == "classic")
        #expect(on(2026, 5, 31) == "classic")
        #expect(on(2026, 6, 1) == "metalhead")
        #expect(on(2026, 6, 30) == "metalhead")
        #expect(on(2026, 7, 1) == "classic")
    }

    @Test func theEasterBunnyComesFromPalmSundayToEasterMonday() {
        #expect(on(2026, 3, 28) == "classic")
        #expect(on(2026, 3, 29) == "bunny")
        #expect(on(2026, 4, 6) == "bunny")
        #expect(on(2026, 4, 7) == "classic")
        // Across the turn of a month, and in a leap year.
        #expect(on(2027, 3, 20) == "classic")
        #expect(on(2027, 3, 21) == "bunny")
        #expect(on(2027, 3, 29) == "bunny")
        #expect(on(2027, 3, 30) == "classic")
        #expect(on(2024, 4, 1) == "bunny")
        #expect(on(2024, 4, 2) == "classic")
    }

    @Test func aSushiChosenInSettingsFliesAllYear() {
        #expect(Looks.resolve("santa", year: 2026, month: 7, day: 1) == "santa")
        #expect(Looks.resolve("classic", year: 2026, month: 12, day: 24) == "classic")
        #expect(Looks.resolve(Looks.byTheCalendar, year: 2026, month: 12, day: 24) == "santa")
    }

    @Test func theSushiDefaultsToTheCalendarAndRefusesAnUnknownOne() {
        #expect(Settings().sushi == Looks.byTheCalendar)
        #expect(Settings(values: ["sushi": "bunny"]).sushi == "bunny")
        #expect(Settings(values: ["sushi": "tuna"]).sushi == Looks.byTheCalendar)
    }

    @Test func theBundledSushisAreTheChoicesInSettingsWithTheirImages() throws {
        let data = try Data(contentsOf: repository.appending(path: "Resources/sushis.json"))
        let looks = try #require(Looks.decode(data)).looks
        #expect(looks.map(\.id) == Array(Settings.Choices.sushi.dropFirst()))
        #expect(looks.first == .classic)
        for look in looks {
            #expect(!look.name.isEmpty)
            #expect(look.images["body"] != nil, "\(look.id) has no body")
            for file in look.images.values {
                #expect(FileManager.default.fileExists(atPath: repository.appending(path: "Resources/\(file)").path), "\(file) is missing")
            }
        }
        #expect(looks.filter(\.hasPropeller).map(\.id) == ["classic"])
    }

    @Test func pointsAreMeasuredFromTheSushisCentreAndTallArtLiftsTheBubble() {
        let look = Look(id: "test", name: "Test", points: ["can": CGPoint(x: 45, y: 15)], top: -5)
        #expect(look.offset(of: "can", size: 180) == CGPoint(x: 45, y: -45))
        #expect(look.offset(of: "basket", size: 180) == nil)
        #expect(look.bubbleLift(size: 180) == 27)
        #expect(Look.classic.bubbleLift(size: 180) == 0)
        #expect(Look(id: "low", name: "Low", top: 9).bubbleLift(size: 180) == 0)
    }
}

// How each sushi moves: the same cases as windows/test/looks.test.js.
@MainActor
struct LookMotionTests {
    private let looks = (try? Data(contentsOf: repository.appending(path: "Resources/sushis.json"))).flatMap(Looks.decode)?.looks ?? []
    private let times = (0..<72).map { Double($0) / 10 }

    private func flight(_ id: String, hover: TimeInterval? = nil) -> Flight {
        var flight = Flight.preview(on: CGSize(width: 1600, height: 900), look: looks.first { $0.id == id } ?? .classic)
        if let hover { flight.hover = hover }
        return flight
    }

    @Test func noSushiJumpsAtTheHoverHeldOrNot() {
        #expect(looks.count == 6)
        for look in looks {
            for hover in [3.2, 1.25] {
                let flight = flight(look.id, hover: hover)
                for edge in [flight.flyIn, flight.flyIn + hover] {
                    let before = flight.pose(at: edge - 1e-6)
                    let after = flight.pose(at: edge + 1e-6)
                    #expect(hypot(before.center.x - after.center.x, before.center.y - after.center.y) < 0.01, "\(look.id) at \(edge)s")
                    #expect(abs(before.tilt - after.tilt) < 0.01, "\(look.id) tilt at \(edge)s")
                }
            }
        }
    }

    @Test func theEasterBunnyHopsUpFromTheLineNeverBelowIt() {
        let bunny = flight("bunny")
        #expect(times.allSatisfy { bunny.pose(at: $0).center.y <= bunny.altitude + 1e-9 })
        #expect(times.contains { bunny.pose(at: $0).center.y < bunny.altitude - 20 })
    }

    @Test func metalheadHeadbangsOnlyWhileItHovers() {
        let metal = flight("metalhead")
        let classic = flight("classic")
        for time in times where time < metal.flyIn || time > metal.flyIn + metal.hover {
            #expect(abs(metal.pose(at: time).tilt - classic.pose(at: time).tilt) < 1e-9, "at \(time)s")
        }
        #expect(times.contains { abs(metal.pose(at: $0).tilt - classic.pose(at: $0).tilt) > 8 })
    }

    @Test func eachSushiBringsItsOwnEffectsAtTheirMomentsTheClassicNone() throws {
        let at = { (id: String, time: TimeInterval) in self.flight(id).effects(at: time) }
        let flyIn = flight("classic").flyIn
        #expect(times.allSatisfy { at("classic", $0).isEmpty })
        // Santa's sparkles trail it only while it moves.
        #expect(!at("santa", 1.0).isEmpty)
        #expect(at("santa", flyIn + 1.5).isEmpty)
        // The bunny drops its egg once it hovers, and the egg falls.
        #expect(at("bunny", flyIn + 0.7).isEmpty)
        let falling = try [0.9, 1.0, 1.1].map { try #require(at("bunny", flyIn + $0).first).y }
        #expect(falling[0] < falling[1] && falling[1] < falling[2])
        // J-Day's can foams as it arrives, then stops.
        #expect(at("jday", flyIn + 0.2).contains { $0.glyph == "bubble" })
        #expect(!at("jday", flyIn + 2).contains { $0.glyph == "bubble" || $0.isWord })
        // Rainy Day's leaves blow by the whole way.
        #expect(times.allSatisfy { at("rainy", $0).count == 3 })
        for look in looks {
            for time in times {
                for effect in at(look.id, time) {
                    #expect((0...1).contains(effect.opacity), "\(look.id) \(effect.glyph) at \(time)s")
                }
            }
        }
    }
}
