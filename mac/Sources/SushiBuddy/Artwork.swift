import AppKit

@MainActor
enum Artwork {
    /// Both layers are rendered from the SVG's full 60×60 viewBox, so they overlay 1:1.
    static let body = image(named: "body")
    static let propeller = image(named: "propeller")

    /// Where the propeller's stem sits within the viewBox: the axis it spins around.
    static let propellerAxis = (x: 29.05 / 60, y: 8.5 / 60)

    static let menuBarIcon: NSImage = {
        let icon = image(named: "MenuBarIcon")
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()

    private static func image(named name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "fish", accessibilityDescription: name) ?? NSImage()
        }
        return image
    }
}
