import Foundation

/// The lines live in `Resources/motivation.json`, shared with the Windows app.
enum Motivation {
    static let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "motivation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lines = try? JSONDecoder().decode([String].self, from: data),
              !lines.isEmpty
        else { return ["You've got this!"] }
        return lines
    }()

    static func random() -> String {
        lines.randomElement() ?? "You've got this!"
    }
}
