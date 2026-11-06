import Foundation

/// What the sushi says. The same rules as windows/lines.js.
///
/// `Resources/lines.json` holds a list per occasion. A lines.json of your own (Settings →
/// Edit Lines…) has the same shape; each list in it replaces the built-in one, and an
/// occasion it leaves out keeps the built-in lines.
enum Lines {
    typealias Book = [String: [String]]

    static let categories = [
        "anytime", "morning", "lateNight", "monday", "friday", "streak", "welcomeBack", "break",
        "claudeDone", "claudeNeedsYou", "pomodoroDone", "pomodoroBreakOver",
    ]
    static let fallback = "You've got this!"

    static func decode(_ data: Data) -> Book? {
        (try? JSONSerialization.jsonObject(with: data)).flatMap(book(from:))
    }

    /// The built-in lines with the person's own on top, and what was wrong with theirs, if anything.
    static func merge(bundled: Book, user: Data?) -> (lines: Book, error: String?) {
        guard let user else { return (bundled, nil) }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: user, options: [.fragmentsAllowed])
        } catch {
            return (bundled, "Your lines.json isn't valid JSON, so the built-in lines are used.")
        }
        guard let own = book(from: parsed) else {
            return (bundled, "Your lines.json should be an object of lists, so the built-in lines are used.")
        }
        return (bundled.merging(own) { _, mine in mine }, nil)
    }

    /// The usable lists in a parsed file. A plain list, the 1.3 shape, is lines for any time.
    private static func book(from parsed: Any) -> Book? {
        if let list = parsed as? [Any] {
            return usable(list).map { ["anytime": $0] } ?? [:]
        }
        guard let object = parsed as? [String: Any] else { return nil }
        var book = Book()
        for category in categories {
            if let list = object[category] as? [Any], let lines = usable(list) {
                book[category] = lines
            }
        }
        return book
    }

    private static func usable(_ list: [Any]) -> [String]? {
        let lines = list.compactMap { $0 as? String }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.isEmpty ? nil : lines
    }

    /// The occasions that fit this moment: morning 5–11, late night 22–5, Monday, Friday.
    static func occasions(at date: Date, calendar: Calendar = .current) -> [String] {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        var found: [String] = []
        if hour >= 5 && hour < 11 { found.append("morning") }
        if hour >= 22 || hour < 5 { found.append("lateNight") }
        if weekday == 2 { found.append("monday") }
        if weekday == 6 { found.append("friday") }
        return found
    }

    struct Moment {
        var date: Date
        var contextLines = true
        var streak: (days: Int, firstToday: Bool)?
        var project: String?
        var calendar = Calendar.current
    }

    /// One line for a flight. `kind` is "motivate" or an occasion of its own ("break", "claudeDone", …).
    /// A motivation is the streak line on the first one of a day from day 2 on; otherwise, with
    /// occasions on, a coin toss between the lines for this moment and the anytime lines.
    static func pick(
        _ kind: String,
        from lines: Book,
        at moment: Moment,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> String {
        func choose(_ list: [String]) -> String? {
            list.isEmpty ? nil : list[min(Int(random() * Double(list.count)), list.count - 1)]
        }
        let text: String?
        if kind == "motivate" {
            if let streak = moment.streak, streak.firstToday, streak.days >= 2, let lines = lines["streak"], !lines.isEmpty {
                text = choose(lines)
            } else {
                let fitting = moment.contextLines
                    ? occasions(at: moment.date, calendar: moment.calendar).flatMap { lines[$0] ?? [] }
                    : []
                text = !fitting.isEmpty && random() < 0.5 ? choose(fitting) : choose(lines["anytime"] ?? [])
            }
        } else {
            let own = lines[kind] ?? []
            text = choose(own.isEmpty ? lines["anytime"] ?? [] : own)
        }
        return fill(text ?? fallback, days: moment.streak?.days, project: moment.project)
    }

    static func fill(_ text: String, days: Int?, project: String?) -> String {
        let name = project.flatMap { $0.isEmpty ? nil : $0 } ?? "your project"
        return text
            .replacingOccurrences(of: "{days}", with: String(days ?? 1))
            .replacingOccurrences(of: "{project}", with: name)
    }
}

/// The days in a row with a motivation.
struct Streak: Codable, Equatable, Sendable {
    var days: Int
    var lastDay: String

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The same day keeps it, the next day adds one, a gap starts over.
    static func advance(_ streak: Streak?, to date: Date, calendar: Calendar = .current) -> (streak: Streak, firstToday: Bool) {
        let today = dayKey(date, calendar: calendar)
        if let streak, streak.lastDay == today { return (streak, false) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date).map { dayKey($0, calendar: calendar) }
        let days = streak?.lastDay == yesterday ? (streak?.days ?? 0) + 1 : 1
        return (Streak(days: days, lastDay: today), true)
    }
}
