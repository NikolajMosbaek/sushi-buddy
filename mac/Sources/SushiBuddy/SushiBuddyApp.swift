import AppKit
import SwiftUI

@main
struct SushiBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AutoMotivate.defaultsKey) private var autoMotivateSeconds = 0

    var body: some Scene {
        MenuBarExtra {
            Button("Motivate me") { appDelegate.flights.launch() }
            Picker("Auto-motivate", selection: autoMotivateSelection) {
                ForEach(AutoMotivate.presets, id: \.seconds) { preset in
                    Text(preset.label).tag(preset.seconds)
                }
            }
            Divider()
            Button("Quit Sushi Buddy") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: Artwork.menuBarIcon)
        }
    }

    private var autoMotivateSelection: Binding<Int> {
        Binding(
            get: { autoMotivateSeconds },
            set: { appDelegate.autoMotivate.set($0) }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let flights = FlightController()
    lazy var autoMotivate = AutoMotivate { [flights] in flights.launch() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--preview"), arguments.indices.contains(flag + 1) {
            PreviewSheet.write(to: URL(fileURLWithPath: arguments[flag + 1]))
            NSApp.terminate(nil)
            return
        }
        autoMotivate.start()
        if arguments.contains("--fly") {
            flights.launch()
        }
    }
}
