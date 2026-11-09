import CoreGraphics
import Foundation

/// One sushi the app can fly as (Settings → Flights → Sushi): its name, its images and the points its
/// animation needs, from Resources/sushis.json, which Art/render-sushis.js writes. Points are in the
/// classic art's units: its 60×60 frame, which a flight draws `size` wide around the sushi's centre.
struct Look: Equatable, Sendable {
    let id: String
    let name: String
    var images: [String: String] = [:]
    var points: [String: CGPoint] = [:]
    /// The highest the art reaches; the classic propeller's top is 4.
    var top: Double = 4

    static let classic = Look(id: "classic", name: "Classic Sushi", images: ["body": "body.png", "propeller": "propeller.png"])

    var hasPropeller: Bool { images["propeller"] != nil }

    /// What floats up when it's petted, in place of the hearts.
    var petGlyph: String? { id == "metalhead" ? "🤘" : nil }

    /// How far a point is from the sushi's centre in a flight `size` wide, before any tilt.
    func offset(of point: String, size: CGFloat) -> CGPoint? {
        points[point].map { CGPoint(x: ($0.x - 30) * size / 60, y: ($0.y - 30) * size / 60) }
    }

    /// How much higher the speech bubble sits than over the classic sushi, to clear ears and hats.
    func bubbleLift(size: CGFloat) -> CGFloat {
        max(0, Look.classic.top - top) * size / 60
    }
}

/// The sushis there are, and which one flies: the one chosen in Settings, or by the calendar.
/// windows/looks.js has the same rules.
enum Looks {
    static let byTheCalendar = "calendar"

    struct Manifest: Decodable {
        struct Stage: Decodable { let min: Double; let size: Double }
        struct Entry: Decodable {
            let id: String
            let name: String
            let images: [String: String]
            let points: [String: [String: Double]]
            let extent: [String: Double]
        }

        let stage: Stage
        let sushis: [Entry]
    }

    static func decode(_ data: Data) -> (stage: Manifest.Stage, looks: [Look])? {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        let looks = manifest.sushis.map { entry in
            Look(
                id: entry.id,
                name: entry.name,
                images: entry.images,
                points: entry.points.compactMapValues { point in
                    guard let x = point["x"], let y = point["y"] else { return nil }
                    return CGPoint(x: x, y: y)
                },
                top: entry.extent["top"] ?? Look.classic.top
            )
        }
        return (manifest.stage, looks)
    }

    private static let bundled = Bundle.main.url(forResource: "sushis", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(decode)

    /// Every sushi, classic first, in the order Settings lists them.
    static let all: [Look] = bundled?.looks ?? [.classic]

    /// The square, in classic units, that a seasonal sushi's images cover.
    static let stage = bundled?.stage ?? Manifest.Stage(min: -20, size: 100)

    static func named(_ id: String) -> Look {
        all.first { $0.id == id } ?? all.first ?? .classic
    }

    /// The sushi to fly today, for the choice in Settings.
    static func current(_ choice: String, on date: Date = .now, calendar: Calendar = .current) -> Look {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return named(resolve(choice, year: day.year ?? 2026, month: day.month ?? 1, day: day.day ?? 1))
    }

    static func resolve(_ choice: String, year: Int, month: Int, day: Int) -> String {
        choice == byTheCalendar ? seasonal(year: year, month: month, day: day) : choice
    }

    /// Which sushi the calendar picks on a day: Fall all September, J-Day from J-dag (the first
    /// Friday of November) to the end of November, Santa 1–26 December, the Easter Bunny from Palm
    /// Sunday to Easter Monday, Metalhead all June (Copenhell), and the classic the rest of the year.
    static func seasonal(year: Int, month: Int, day: Int) -> String {
        switch month {
        case 6: return "metalhead"
        case 9: return "fall"
        case 11: return day >= firstFridayOfNovember(year) ? "jday" : "classic"
        case 12: return day <= 26 ? "santa" : "classic"
        default:
            let today = dayOfYear(year: year, month: month, day: day)
            let easter = easterSunday(year)
            let easterDay = dayOfYear(year: year, month: easter.month, day: easter.day)
            return (easterDay - 7...easterDay + 1).contains(today) ? "bunny" : "classic"
        }
    }

    /// Easter Sunday in the Gregorian calendar (the Meeus/Jones/Butcher algorithm).
    static func easterSunday(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }

    /// The day of November that is its first Friday.
    static func firstFridayOfNovember(_ year: Int) -> Int {
        let friday = 5 // counting from Sunday = 0
        return 1 + (friday - weekday(year: year, month: 11, day: 1) + 7) % 7
    }

    /// Sunday = 0 … Saturday = 6 (Sakamoto's method), so no time zone gets a say.
    static func weekday(year: Int, month: Int, day: Int) -> Int {
        let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = month < 3 ? year - 1 : year
        return (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + day) % 7
    }

    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return lengths.prefix(month - 1).reduce(0, +) + day
    }
}
