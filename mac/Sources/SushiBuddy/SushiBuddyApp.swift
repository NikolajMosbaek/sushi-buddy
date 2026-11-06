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
            Toggle("Launch at Login", isOn: launchAtLoginSelection)
            Divider()
            if let update = appDelegate.updates.available {
                Button("Update to \(update.version?.description ?? update.tagName)…") {
                    appDelegate.updates.download(update)
                }
            } else {
                Button("Check for Updates…") {
                    Task { await appDelegate.updates.checkAndTell() }
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

    private var launchAtLoginSelection: Binding<Bool> {
        Binding(
            get: { appDelegate.launchAtLogin.isEnabled },
            set: { appDelegate.launchAtLogin.set($0) }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let flights = FlightController()
    let updates = Updates()
    let launchAtLogin = LaunchAtLogin()
    lazy var autoMotivate = AutoMotivate { [flights] in flights.launch() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--preview"), arguments.indices.contains(flag + 1) {
            PreviewSheet.write(to: URL(fileURLWithPath: arguments[flag + 1]))
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--focus-status") {
            Task {
                let access = await FocusStatus.requestAccess()
                print("Focus access: \(access.rawValue) (3 = allowed), Focus on: \(FocusStatus.isFocused)")
                NSApp.terminate(nil)
            }
            return
        }
        // --launch-at-login on|off|status: for setting it up from a script.
        if let flag = arguments.firstIndex(of: "--launch-at-login") {
            let choice = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "status"
            if choice == "on" || choice == "off" { launchAtLogin.set(choice == "on") }
            print("Launch at Login: \(launchAtLogin.status)")
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--check-updates") {
            Task {
                print("Installed \(updates.current?.description ?? "?"): \(await updates.check())")
                NSApp.terminate(nil)
            }
            return
        }
        autoMotivate.start()
        updates.startQuietChecks()
        if arguments.contains("--fly") {
            flights.launch()
        }
    }
}
