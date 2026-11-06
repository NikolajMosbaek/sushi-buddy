import AppKit
import SwiftUI

/// The Settings window, opened from the menu (⌘,). Every change applies at once.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    func show(sushi: Sushi, launchAtLogin: LaunchAtLogin) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(
                preferences: sushi.preferences, sushi: sushi, launchAtLogin: launchAtLogin
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "Sushi Buddy Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        sushi.loadLines()
        launchAtLogin.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// `--preview-settings <folder>`: draws each tab to settings-<tab>.png, for checking the
    /// window without looking at the screen.
    static func writePreviews(to folder: URL, sushi: Sushi, launchAtLogin: LaunchAtLogin) async {
        sushi.loadLines()
        for tab in SettingsTab.allCases {
            let controller = NSHostingController(rootView: SettingsView(
                preferences: sushi.preferences, sushi: sushi, launchAtLogin: launchAtLogin, tab: tab
            ))
            let window = NSWindow(contentViewController: controller)
            window.alphaValue = 0
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))
            if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let file = folder.appending(path: "settings-\(tab.rawValue).png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
                print(file.path)
            }
            window.orderOut(nil)
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case general, automatic, quiet, lines, claude
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let sushi: Sushi
    let launchAtLogin: LaunchAtLogin
    @State var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(settings: $preferences.settings, sushi: sushi, launchAtLogin: launchAtLogin)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AutomaticTab(settings: $preferences.settings, sushi: sushi)
                .tabItem { Label("Automatic", systemImage: "timer") }
                .tag(SettingsTab.automatic)
            QuietTab(settings: $preferences.settings)
                .tabItem { Label("Quiet", systemImage: "moon.zzz") }
                .tag(SettingsTab.quiet)
            LinesTab(settings: $preferences.settings, sushi: sushi)
                .tabItem { Label("Lines", systemImage: "text.bubble") }
                .tag(SettingsTab.lines)
            ClaudeTab(settings: $preferences.settings, sushi: sushi)
                .tabItem { Label("Claude Code", systemImage: "sparkles") }
                .tag(SettingsTab.claude)
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralTab: View {
    @Binding var settings: Settings
    let sushi: Sushi
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                Picker("Shortcut for Motivate me", selection: $settings.hotkey) {
                    ForEach(Hotkey.presets, id: \.id) { Text($0.label).tag($0.id) }
                }
                if let problem = sushi.hotkeyProblem { Problem(problem) }
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
            }
            Section("Flights") {
                Picker("Flight path", selection: $settings.flightPath) {
                    Text("Any, at random").tag("random")
                    Text("Straight across").tag("classic")
                    Text("Loop-the-loop").tag("loop")
                    Text("Bounce").tag("bounce")
                    Text("Zigzag").tag("zigzag")
                }
                Toggle("Pet the sushi: click it mid-flight", isOn: $settings.petting)
                Picker("Sound", selection: $settings.sound) {
                    Text("Off").tag("off")
                    Text("Chime").tag("chime")
                    Text("Propeller whirr").tag("whirr")
                }
                HStack {
                    Spacer()
                    Button("Try It") { sushi.fly("motivate") }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AutomaticTab: View {
    @Binding var settings: Settings
    let sushi: Sushi

    var body: some View {
        Form {
            Section {
                Picker("Auto-motivate", selection: $settings.autoMotivateSeconds) {
                    Text("Off").tag(0)
                    Text("Every 15 minutes").tag(900)
                    Text("Every 30 minutes").tag(1800)
                    Text("Every hour").tag(3600)
                    Text("Every 2 hours").tag(7200)
                    Text("Every 4 hours").tag(14400)
                }
                Picker("Break reminders", selection: $settings.breakReminderMinutes) {
                    Text("Off").tag(0)
                    ForEach([30, 45, 60, 90], id: \.self) { Text("After \($0) min at the computer").tag($0) }
                }
                Toggle("Welcome back after you've been away", isOn: $settings.welcomeBack)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Five minutes away from the keyboard counts as a break. These hold off while a rule under Quiet holds.")
                    if let skip = sushi.lastSkip {
                        Text("Last skipped at \(skip.at.formatted(date: .omitted, time: .shortened)): \(skip.occasion), because \(skip.reason.explanation).")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Pomodoro") {
                Picker("Focus", selection: $settings.pomodoroFocusMinutes) {
                    ForEach(Settings.Choices.pomodoroFocusMinutes, id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Break", selection: $settings.pomodoroBreakMinutes) {
                    ForEach(Settings.Choices.pomodoroBreakMinutes, id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("A 15-minute break after every fourth", isOn: $settings.pomodoroLongBreaks)
                HStack {
                    if let pomodoro = sushi.pomodoro {
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            Text(pomodoro.describe(at: context.date)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Stop") { sushi.stopPomodoro() }
                    } else {
                        Text("The sushi tells you when to break and when to start again.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Start") { sushi.startPomodoro() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct QuietTab: View {
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("A Focus or Do Not Disturb is on", isOn: $settings.quietDuringFocus)
                Toggle("You're on a call (microphone or camera in use)", isOn: $settings.quietOnCalls)
                Toggle("An app is full screen or presenting", isOn: $settings.quietWhenPresenting)
                Toggle("You're away (screen locked or idle)", isOn: $settings.quietWhenAway)
                Picker("Away after", selection: $settings.awayMinutes) {
                    ForEach(Settings.Choices.awayMinutes, id: \.self) { Text("\($0) min idle").tag($0) }
                }
            } header: {
                Text("Automatic flights hold off while")
            } footer: {
                Footer("Automatic: Auto-motivate, break reminders, welcome back and Claude Code. What you ask for (Motivate me, the shortcut, a Pomodoro) always flies.")
            }
            Section("Right now") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(SystemSignals.describe(awayMinutes: settings.awayMinutes), id: \.self) { Text($0) }
                    }
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                }
                if FocusStatus.authorization != .authorized {
                    HStack {
                        Text("Sushi Buddy can't see your Focus until you allow it.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LinesTab: View {
    @Binding var settings: Settings
    let sushi: Sushi

    var body: some View {
        Form {
            Section {
                Toggle("Lines for the time and day (morning, late night, Monday, Friday)", isOn: $settings.contextLines)
                Toggle("Streaks: “Day 5 in a row!” on the first motivation of a day", isOn: $settings.streaks)
                if let streak = sushi.preferences.streak {
                    Text("Current streak: \(streak.days) day\(streak.days == 1 ? "" : "s"), last on \(streak.lastDay).")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if let problem = sushi.linesProblem {
                    Problem(problem)
                } else {
                    Text(sushi.hasOwnLines ? "Using your lines.json." : "Using the built-in lines.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Edit Lines…") { sushi.editLines() }
                    Button("Show in Finder") { sushi.revealLines() }.disabled(!sushi.hasOwnLines)
                    Spacer()
                    Button("Reset to Built-in") { sushi.resetLines() }.disabled(!sushi.hasOwnLines)
                }
            } header: {
                Text("Your lines")
            } footer: {
                Footer("Edit Lines opens a copy of the built-in lines.json. Each list you keep replaces that occasion's lines; {days} and {project} are filled in. Changes count from the next flight.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeTab: View {
    @Binding var settings: Settings
    let sushi: Sushi

    static let install = "claude plugin install sushi-buddy --marketplace NikolajMosbaek/sushi-buddy"

    var body: some View {
        Form {
            Section {
                Toggle("Listen for Claude Code and scripts on 127.0.0.1:\(String(Listener.port))", isOn: $settings.listen)
                if let problem = sushi.listenerProblem { Problem(problem) }
                Toggle("Cheer when Claude finishes", isOn: $settings.claudeDone)
                Picker("…a turn longer than", selection: $settings.claudeMinMinutes) {
                    Text("Any length").tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
                .disabled(!settings.claudeDone)
                Toggle("Fly when Claude needs your permission", isOn: $settings.claudeNeedsYou)
                if let heard = sushi.claudeLastHeard {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Last heard from Claude Code \(heard.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not heard from Claude Code since Sushi Buddy started.").foregroundStyle(.secondary)
                }
            }
            Section {
                Text(verbatim: Self.install)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.install, forType: .string)
                    }
                }
            } header: {
                Text("Connect Claude Code once, in a terminal")
            } footer: {
                Footer("The plugin sends Claude Code's prompt, stop and permission events here.")
            }
            Section {
                Text(verbatim: "curl -d 'Deployed! 🚀' http://127.0.0.1:\(Listener.port)/fly")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("Scripts can fly the sushi too")
            }
        }
        .formStyle(.grouped)
    }
}

private struct Footer: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Problem: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }
}
