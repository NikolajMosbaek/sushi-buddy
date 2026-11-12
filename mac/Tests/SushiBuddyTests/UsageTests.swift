import Foundation
import Testing

@testable import SushiBuddy

// The same cases as windows/test/usage.test.js, so both apps send the same summary.

private let id = "00000000-0000-4000-8000-000000000000"
private let env = Usage.Environment(
    version: "1.8",
    build: "12",
    operatingSystem: "macOS",
    systemVersion: "15.1.0",
    systemMajorVersion: "15",
    architecture: "arm64",
    isDebug: false,
    installSource: "homebrew"
)

private func with(_ change: (inout Settings) -> Void) -> Settings {
    var settings = Settings()
    change(&settings)
    return settings
}

struct UsageTests {
    @Test func hashesTheRandomIDTheSameWayOnBothPlatforms() {
        #expect(Usage.hash(id) == "db8055e0e0307d5a016bec4dc338d69875eb0fb7e614a8b125b08fb082095d98")
    }

    @Test func aFlightCountsUnderWhatStartedIt() {
        #expect(Usage.trigger("motivate", automatic: false) == "menu")
        #expect(Usage.trigger("motivate", automatic: true) == "auto")
        #expect(Usage.trigger("motivate", automatic: false, via: "shortcut") == "shortcut")
        #expect(Usage.trigger("motivate", automatic: false, via: "script") == "script")
        #expect(Usage.trigger("break", automatic: true) == "break")
        #expect(Usage.trigger("welcomeBack", automatic: true) == "welcomeBack")
        #expect(Usage.trigger("pomodoroDone", automatic: false) == "pomodoro")
        #expect(Usage.trigger("pomodoroBreakOver", automatic: false) == "pomodoro")
        #expect(Usage.trigger("claudeDone", automatic: true) == "claudeDone")
        #expect(Usage.trigger("claudeNeedsYou", automatic: true) == "claudeNeedsYou")
    }

    @Test func countsAddUpPerKey() {
        var record = Usage.Record(id: id)
        record = Usage.count(record, "flight.menu")
        record = Usage.count(record, "flight.menu")
        record = Usage.count(record, "pet")
        #expect(record.counts == ["flight.menu": 2, "pet": 1])
    }

    @Test func onlySettingsThatDifferFromTheDefaultCountAsChangedAndNeverSharingItself() {
        #expect(Usage.changedKeys(with { $0.shareUsage = true }).isEmpty)
        let changed = with {
            $0.sound = "chime"
            $0.petting = false
            $0.shareUsage = true
        }
        #expect(Usage.changedKeys(changed) == ["petting", "sound"])
    }

    @Test func remembersEverySettingEverChangedAlsoOneChangedBack() {
        var record = Usage.Record(id: id)
        record = Usage.noteSettings(record, with { $0.sound = "chime" })
        record = Usage.noteSettings(record, with { $0.welcomeBack = true })
        #expect(record.everChanged == ["sound", "welcomeBack"])
    }

    @Test func isDueOncePerCalendarDay() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 23, minute: 59)))
        let today = Usage.day(date)
        #expect(today == "2026-11-12")
        #expect(Usage.isDue(Usage.Record(id: id), today: today))
        #expect(!Usage.isDue(Usage.Record(id: id, lastSent: "2026-11-12"), today: today))
        #expect(Usage.isDue(Usage.Record(id: id, lastSent: "2026-11-11"), today: today))
    }

    @Test func theSummaryHasTheAppEverySettingAndACountForEveryTriggerAndQuietRule() {
        var record = Usage.Record(id: id)
        record = Usage.count(record, "flight.shortcut")
        record = Usage.count(record, "skip.call")
        record = Usage.count(record, "pet")
        record = Usage.noteSettings(record, with { $0.sound = "chime" })
        let summary = Usage.payload(with {
            $0.sound = "chime"
            $0.shareUsage = true
        }, record, env)

        #expect(summary["TelemetryDeck.AppInfo.version"] == .text("1.8"))
        #expect(summary["TelemetryDeck.AppInfo.versionAndBuildNumber"] == .text("1.8 12"))
        #expect(summary["TelemetryDeck.Device.operatingSystem"] == .text("macOS"))
        #expect(summary["TelemetryDeck.Device.platform"] == .text("macOS"))
        #expect(summary["TelemetryDeck.Device.systemMajorVersion"] == .text("15"))
        #expect(summary["TelemetryDeck.Device.architecture"] == .text("arm64"))
        #expect(summary["TelemetryDeck.RunContext.isDebug"] == .flag(false))
        #expect(summary["Sushi.Install.source"] == .text("homebrew"))
        #expect(summary["Sushi.Settings.sound"] == .text("chime"))
        #expect(summary["Sushi.Settings.autoMotivateSeconds"] == .text("0"))
        #expect(summary["Sushi.Settings.petting"] == .text("true"))
        #expect(summary["Sushi.Settings.shareUsage"] == nil)
        #expect(summary["Sushi.Settings.changedCount"] == .number(1))
        #expect(summary["Sushi.Settings.everChanged"] == .text("sound"))
        #expect(summary["Sushi.Flights.shortcut"] == .number(1))
        #expect(summary["Sushi.Flights.menu"] == .number(0))
        #expect(summary["Sushi.Skips.call"] == .number(1))
        #expect(summary["Sushi.Skips.away"] == .number(0))
        #expect(summary["Sushi.Pets"] == .number(1))
        #expect(summary["Sushi.Health.unexpectedQuits"] == .number(0))
        for trigger in Usage.triggers { #expect(summary["Sushi.Flights.\(trigger)"] != nil) }
        for reason in Usage.quietReasons { #expect(summary["Sushi.Skips.\(reason)"] != nil) }
    }

    @Test func nothingChangedReadsAsNone() {
        let summary = Usage.payload(with { $0.shareUsage = true }, Usage.Record(id: id), env)
        #expect(summary["Sushi.Settings.everChanged"] == .text("none"))
        #expect(summary["Sushi.Settings.changedCount"] == .number(0))
    }

    @Test func theRequestIsOneSignalWithTheHashedIDNeverTheIDItself() throws {
        let body = Usage.body(appID: "APP-ID", record: Usage.Record(id: id), payload: ["Sushi.Pets": .number(0)], testMode: true)
        #expect(body == [
            Usage.Signal(appID: "APP-ID", clientUser: Usage.hash(id), type: "Sushi.dailySummary", isTestMode: true, payload: ["Sushi.Pets": .number(0)]),
        ])
        let json = try #require(Usage.encode(body, pretty: false).flatMap { String(data: $0, encoding: .utf8) })
        #expect(!json.contains(id))
        #expect(json.contains("\"Sushi.Pets\":0"))
    }

    @Test func afterASendOnlyWhatWasSentComesOffTheCounts() {
        var sent = Usage.Record(id: id)
        sent = Usage.count(sent, "flight.menu")
        sent = Usage.count(sent, "pet")
        // A flight while the request was out.
        let now = Usage.count(Usage.count(sent, "flight.menu"), "flight.auto")
        let after = Usage.afterSend(now, sent: sent, today: "2026-11-12")
        #expect(after.counts == ["flight.menu": 1, "flight.auto": 1])
        #expect(after.lastSent == "2026-11-12")
        #expect(after.id == id)
    }

    @Test func aRunThatEndedWhileTheComputerStayedOnCountsAsAnUnexpectedQuit() {
        // Started 600 s ago; the computer has been up for an hour: the app died, the computer didn't.
        #expect(Usage.quitUnexpectedly(runningSince: 1000, now: 1600, uptime: 3600))
        // Up for only 100 s: the computer restarted since, which ends every app.
        #expect(!Usage.quitUnexpectedly(runningSince: 1000, now: 1600, uptime: 100))
        #expect(!Usage.quitUnexpectedly(runningSince: nil, now: 1600, uptime: 3600))
    }
}

@MainActor
@Suite struct UsageReporterRules {
    private func reporter() -> (UsageReporter, Preferences) {
        let name = "SushiBuddyTests.usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults)
        return (UsageReporter(preferences: preferences), preferences)
    }

    @Test func countsNothingWhileSharingIsOff() {
        let (usage, preferences) = reporter()
        usage.launched()
        usage.count("flight.menu")
        #expect(preferences.usage == nil)
    }

    @Test func turningSharingOnMakesAnIDAndOffForgetsItAndEveryCount() throws {
        let (usage, preferences) = reporter()
        preferences.settings.shareUsage = true
        usage.sharingChanged()
        usage.count("flight.menu")
        let record = try #require(preferences.usage)
        #expect(UUID(uuidString: record.id) != nil)
        #expect(record.counts == ["flight.menu": 1])

        preferences.settings.shareUsage = false
        usage.sharingChanged()
        #expect(preferences.usage == nil)

        preferences.settings.shareUsage = true
        usage.sharingChanged()
        #expect(try #require(preferences.usage).id != record.id)
    }

    @Test func whatsSentShowsTheHashNeverTheID() throws {
        let (usage, preferences) = reporter()
        preferences.settings.shareUsage = true
        usage.sharingChanged()
        let id = try #require(preferences.usage).id
        let shown = usage.preview()
        #expect(!shown.contains(id))
        #expect(shown.contains(Usage.hash(id)))
        #expect(shown.contains("Sushi.dailySummary"))
    }

    @Test func aRunThatNeverQuitCountsOnceSharingIsOn() throws {
        let (usage, preferences) = reporter()
        preferences.settings.shareUsage = true
        preferences.runningSince = Date.now.timeIntervalSince1970 - 60
        usage.launched()
        #expect(try #require(preferences.usage).counts["unexpectedQuit"] == 1)
        usage.quitting()
        #expect(preferences.runningSince == nil)
    }
}
