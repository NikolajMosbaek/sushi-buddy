import AppKit
import SwiftUI

@main
struct SushiBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Motivate me") { appDelegate.sushi.fly("motivate") }
            if let pomodoro = appDelegate.sushi.pomodoro {
                Button("Stop Pomodoro (\(pomodoro.describe(at: .now)))") { appDelegate.sushi.stopPomodoro() }
            } else {
                Button("Start Pomodoro") { appDelegate.sushi.startPomodoro() }
            }
            Divider()
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Button("What's New in \(WhatsNew.installed)…") { appDelegate.sushi.showWhatsNew() }
            if let update = appDelegate.updates.available {
                Button("Update to \(update.version?.description ?? update.tagName)…") {
                    appDelegate.updates.download(update)
                }
            } else {
                Button("Check for Updates…") {
                    Task { await appDelegate.updates.checkAndTell() }
                }
            }
            Button("Tip the Sushi…") { appDelegate.sushi.openTipJar() }
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
    let preferences = Preferences()
    let updates = Updates()
    let launchAtLogin = LaunchAtLogin()
    lazy var sushi = Sushi(preferences: preferences, updates: updates)
    private let settingsWindow = SettingsWindow()

    func showSettings() {
        settingsWindow.show(sushi: sushi, launchAtLogin: launchAtLogin)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        // --preview <file.png> [--path loop]: draws a flight to a PNG and quits.
        if let file = value(after: "--preview") {
            PreviewSheet.write(to: URL(fileURLWithPath: file), path: FlightPath(rawValue: value(after: "--path") ?? "") ?? .classic)
            NSApp.terminate(nil)
            return
        }
        if let folder = value(after: "--preview-tour") {
            Task {
                let steps = Tour.steps(on: .mac, shortcut: Hotkey.presets[1].label)
                await TourController.writePreviews(to: URL(fileURLWithPath: folder), preferences: preferences, steps: steps)
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = value(after: "--preview-whats-new") {
            Task {
                let steps = WhatsNew.steps(WhatsNew.bundled, installed: Version(Updates.installedVersion))
                await TourController.writePreviews(to: URL(fileURLWithPath: folder), preferences: preferences, steps: steps, closeTitle: "Close")
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = value(after: "--preview-settings") {
            Task {
                await SettingsWindow.writePreviews(to: URL(fileURLWithPath: folder), sushi: sushi, launchAtLogin: launchAtLogin)
                NSApp.terminate(nil)
            }
            return
        }
        // --status: what the quiet rules see right now.
        if arguments.contains("--status") {
            Task {
                _ = await FocusStatus.requestAccess()
                for line in SystemSignals.describe(awayMinutes: preferences.settings.awayMinutes) { print(line) }
                NSApp.terminate(nil)
            }
            return
        }
        // --launch-at-login on|off|status: for setting it up from a script.
        if arguments.contains("--launch-at-login") {
            let choice = value(after: "--launch-at-login") ?? "status"
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
        sushi.start()
        if arguments.contains("--fly") { sushi.fly("motivate") }
        if arguments.contains("--settings") { showSettings() }
        if arguments.contains("--tour") {
            Task {
                // After the menu bar icon is in place, so the sushi can find it.
                try? await Task.sleep(for: .seconds(1))
                sushi.startTour()
            }
        }
    }
}
