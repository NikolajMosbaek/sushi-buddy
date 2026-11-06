import AppKit
import SwiftUI

@main
struct SushiBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Motivate me") { appDelegate.flights.launch() }
            Divider()
            Button("Quit Sushi Buddy") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: Artwork.menuBarIcon)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let flights = FlightController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--preview"), arguments.indices.contains(flag + 1) {
            PreviewSheet.write(to: URL(fileURLWithPath: arguments[flag + 1]))
            NSApp.terminate(nil)
        } else if arguments.contains("--fly") {
            flights.launch()
        }
    }
}
