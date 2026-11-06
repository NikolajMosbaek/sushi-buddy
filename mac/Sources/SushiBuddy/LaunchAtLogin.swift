import AppKit
import Observation
import ServiceManagement

/// Starts Sushi Buddy when you log in, as a login item of the app itself.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false

    init() {
        refresh()
    }

    var status: String {
        switch SMAppService.mainApp.status {
        case .enabled: "on"
        // macOS answers notFound for an app that has never registered, too.
        case .notRegistered, .notFound: "off"
        case .requiresApproval: "waiting for approval in System Settings → General → Login Items"
        @unknown default: "unknown"
        }
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refresh()
            tell("Couldn't change Launch at Login", error.localizedDescription)
            return
        }
        refresh()
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            askForApproval()
        }
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func askForApproval() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow Sushi Buddy to open at login"
        alert.informativeText = "Turn Sushi Buddy on under Login Items in System Settings."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func tell(_ message: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
