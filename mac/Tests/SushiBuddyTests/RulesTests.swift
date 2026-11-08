import Foundation
import Testing
@testable import SushiBuddy

// The same cases as windows/test/rules.test.js, so both apps keep the same rules.

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}

/// Feeds `pick` a fixed run of "random" numbers.
private func sequence(_ values: [Double]) -> () -> Double {
    var values = values
    return { values.isEmpty ? 0 : values.removeFirst() }
}

private let tuesdayNoon = date(2026, 11, 3)
private let mondayMorning = date(2026, 11, 2, 8)
private let fridayNight = date(2026, 11, 6, 23)

private let bundledLines: Lines.Book = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/lines.json")
    return (try? Data(contentsOf: url)).flatMap(Lines.decode) ?? [:]
}()

@Suite struct SettingsRules {
    @Test func fallsBackToTheDefaultForAnythingMissingOrNotAChoice() {
        #expect(Settings(values: [:]) == Settings())
        let settings = Settings(values: ["autoMotivateSeconds": 1800, "sound": "banjo", "petting": "yes", "welcomeBack": true])
        #expect(settings.autoMotivateSeconds == 1800)
        #expect(settings.sound == "off")
        #expect(settings.petting == true)
        #expect(settings.welcomeBack == true)
    }

    @Test func nothingFliesOrSoundsOnItsOwnByDefaultAndTheQuietRulesStartOn() {
        let defaults = Settings()
        #expect(defaults.autoMotivateSeconds == 0)
        #expect(defaults.breakReminderMinutes == 0)
        #expect(defaults.welcomeBack == false)
        #expect(defaults.sound == "off")
        #expect(defaults.quietDuringFocus && defaults.quietOnCalls && defaults.quietWhenPresenting && defaults.quietWhenAway)
    }

    @Test func storedValuesRoundTrip() {
        var settings = Settings()
        settings.flightPath = "loop"
        settings.claudeMinMinutes = 5
        #expect(Settings(values: settings.values) == settings)
    }

    @MainActor @Test func preferencesStoreAChangeAndHandItOn() throws {
        let suite = "SushiBuddyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        var seen: [Settings] = []
        preferences.onChange = { seen.append($0) }
        preferences.settings.sound = "chime"
        #expect(defaults.string(forKey: "sound") == "chime")
        #expect(seen.map(\.sound) == ["off"])
        #expect(Preferences(defaults: defaults).settings.sound == "chime")
    }
}

@Suite struct LineRules {
    @Test func yourOwnLinesReplaceTheBuiltInOnesPerOccasion() throws {
        let own = Data(#"{"anytime": ["Mine!"], "friday": [], "bogus": ["x"]}"#.utf8)
        let merged = Lines.merge(bundled: bundledLines, user: own)
        #expect(merged.error == nil)
        #expect(merged.lines["anytime"] == ["Mine!"])
        #expect(merged.lines["friday"] == bundledLines["friday"])
        #expect(merged.lines["bogus"] == nil)
    }

    @Test func aPlainListIsAnytimeLinesAndBrokenJSONKeepsTheBuiltInLines() throws {
        #expect(Lines.merge(bundled: bundledLines, user: Data(#"["Old style"]"#.utf8)).lines["anytime"] == ["Old style"])
        let broken = Lines.merge(bundled: bundledLines, user: Data(#"{ "anytime": ["#.utf8))
        #expect(broken.lines == bundledLines)
        #expect(broken.error?.contains("isn't valid JSON") == true)
        #expect(Lines.merge(bundled: bundledLines, user: nil).error == nil)
        #expect(bundledLines["anytime"]?.isEmpty == false)
    }

    @Test func occasionsFollowTheClockAndTheWeekday() {
        #expect(Lines.occasions(at: tuesdayNoon, calendar: calendar) == [])
        #expect(Lines.occasions(at: mondayMorning, calendar: calendar) == ["morning", "monday"])
        #expect(Lines.occasions(at: fridayNight, calendar: calendar) == ["lateNight", "friday"])
    }

    @Test func aMotivationTossesACoinBetweenOccasionAndAnytimeLines() {
        let lines: Lines.Book = ["anytime": ["any"], "morning": ["morning"], "monday": ["monday"]]
        let on = Lines.Moment(date: mondayMorning, contextLines: true, calendar: calendar)
        var off = on
        off.contextLines = false
        #expect(Lines.pick("motivate", from: lines, at: on, random: sequence([0.1, 0.0])) == "morning")
        #expect(Lines.pick("motivate", from: lines, at: on, random: sequence([0.9, 0.0])) == "any")
        #expect(Lines.pick("motivate", from: lines, at: off, random: sequence([0.0, 0.1, 0.0])) == "any")
    }

    @Test func theFirstMotivationOfADayFromDayTwoIsTheStreakLine() {
        let lines: Lines.Book = ["anytime": ["any"], "streak": ["Day {days}!"]]
        func pick(_ days: Int, _ firstToday: Bool) -> String {
            Lines.pick("motivate", from: lines, at: .init(date: tuesdayNoon, streak: (days, firstToday), calendar: calendar), random: { 0 })
        }
        #expect(pick(4, true) == "Day 4!")
        #expect(pick(4, false) == "any")
        #expect(pick(1, true) == "any")
    }

    @Test func otherOccasionsUseTheirOwnLinesAndFillInTheProject() {
        let lines: Lines.Book = ["anytime": ["any"], "claudeDone": ["Done in {project}"]]
        #expect(Lines.pick("claudeDone", from: lines, at: .init(date: tuesdayNoon, project: "sushi"), random: { 0 }) == "Done in sushi")
        #expect(Lines.pick("claudeDone", from: lines, at: .init(date: tuesdayNoon), random: { 0 }) == "Done in your project")
        #expect(Lines.pick("break", from: lines, at: .init(date: tuesdayNoon), random: { 0 }) == "any")
    }

    @Test func aStreakGrowsOnConsecutiveDaysHoldsWithinADayAndStartsOverAfterAGap() {
        let first = Streak.advance(nil, to: tuesdayNoon, calendar: calendar)
        #expect(first.streak == Streak(days: 1, lastDay: "2026-11-03"))
        #expect(first.firstToday)
        #expect(Streak.advance(first.streak, to: date(2026, 11, 3, 18), calendar: calendar).firstToday == false)
        #expect(Streak.advance(first.streak, to: date(2026, 11, 4, 9), calendar: calendar).streak == Streak(days: 2, lastDay: "2026-11-04"))
        #expect(Streak.advance(first.streak, to: date(2026, 11, 6, 9), calendar: calendar).streak == Streak(days: 1, lastDay: "2026-11-06"))
        #expect(Streak.advance(Streak(days: 5, lastDay: "2026-10-31"), to: date(2026, 11, 1, 9), calendar: calendar).streak.days == 6)
    }
}

@Suite struct PresenceRules {
    @Test func theQuietRulesGiveTheFirstReasonThatHoldsAndIsSwitchedOn() {
        let all = QuietSignals(away: true, focus: true, call: true, presenting: true)
        var settings = Settings()
        #expect(Quiet.reason(settings, all) == .away)
        settings.quietWhenAway = false
        #expect(Quiet.reason(settings, all) == .focus)
        settings.quietDuringFocus = false
        #expect(Quiet.reason(settings, all) == .call)
        #expect(Quiet.reason(Settings(), QuietSignals(presenting: true)) == .presenting)
        var noPresenting = Settings()
        noPresenting.quietWhenPresenting = false
        #expect(Quiet.reason(noPresenting, QuietSignals(presenting: true)) == nil)
        #expect(Quiet.reason(Settings(), QuietSignals()) == nil)
        var allOff = Settings()
        allOff.quietWhenAway = false
        allOff.quietDuringFocus = false
        allOff.quietOnCalls = false
        allOff.quietWhenPresenting = false
        #expect(Quiet.reason(allOff, all) == nil)
    }

    @Test func awayMeansLockedOrIdleForTheChosenMinutes() {
        #expect(Quiet.isAway(idleSeconds: 599, locked: false, awayMinutes: 10) == false)
        #expect(Quiet.isAway(idleSeconds: 600, locked: false, awayMinutes: 10))
        #expect(Quiet.isAway(idleSeconds: 0, locked: true, awayMinutes: 10))
    }

    @Test func comingBackIsNoticedOnceWithHowLongYouWereAway() {
        let t = { (seconds: Double) in Date(timeIntervalSince1970: seconds) }
        var presence = Presence()
        let result1 = presence.tick(now: t(1000), away: true, idleSeconds: 600)
        #expect(result1.cameBack == false)
        #expect(presence.awaySince == t(400))
        _ = presence.tick(now: t(2000), away: true, idleSeconds: 1600)
        #expect(presence.awaySince == t(400))
        let back = presence.tick(now: t(2100), away: false, idleSeconds: 2)
        #expect(back.cameBack)
        #expect(back.awayFor == 1700)
        let result2 = presence.tick(now: t(2200), away: false, idleSeconds: 1)
        #expect(result2.cameBack == false)
    }

    @Test func aBreakReminderComesAfterTheIntervalAndFiveIdleMinutesCountAsABreak() {
        let minute = { (count: Double) in Date(timeIntervalSince1970: count * 60) }
        var timer = BreakTimer(activeSince: minute(0))
        let result3 = timer.tick(now: minute(44), idleSeconds: 0, intervalMinutes: 45)
        #expect(result3 == false)
        let result4 = timer.tick(now: minute(45), idleSeconds: 0, intervalMinutes: 45)
        #expect(result4)
        #expect(timer.activeSince == minute(45))
        var rested = BreakTimer(activeSince: minute(0))
        _ = rested.tick(now: minute(40), idleSeconds: 300, intervalMinutes: 45)
        let result5 = rested.tick(now: minute(80), idleSeconds: 0, intervalMinutes: 45)
        #expect(result5 == false)
        var off = BreakTimer(activeSince: minute(0))
        let result6 = off.tick(now: minute(999), idleSeconds: 0, intervalMinutes: 0)
        #expect(result6 == false)
    }
}

@Suite struct PomodoroRules {
    @Test func alternatesFocusAndBreaksWithEveryFourthBreakLong() {
        let settings = Settings()
        var pomodoro = Pomodoro.start(at: Date(timeIntervalSince1970: 0), settings)
        #expect(pomodoro == Pomodoro(phase: .focus, endsAt: Date(timeIntervalSince1970: 25 * 60), completed: 0))
        var phases: [String] = []
        for _ in 0..<8 {
            let next = pomodoro.next(at: pomodoro.endsAt, settings)
            phases.append("\(next.pomodoro.phase.rawValue):\(next.line)")
            pomodoro = next.pomodoro
        }
        #expect(phases == [
            "break:pomodoroDone", "focus:pomodoroBreakOver", "break:pomodoroDone", "focus:pomodoroBreakOver",
            "break:pomodoroDone", "focus:pomodoroBreakOver", "longBreak:pomodoroDone", "focus:pomodoroBreakOver",
        ])
        var noLong = settings
        noLong.pomodoroLongBreaks = false
        let third = Pomodoro(phase: .focus, endsAt: .distantPast, completed: 3)
        #expect(third.next(at: .now, noLong).pomodoro.phase == .shortBreak)
        let zero = Date(timeIntervalSince1970: 0)
        #expect(Pomodoro(phase: .focus, endsAt: zero.addingTimeInterval(12 * 60 + 0.001), completed: 0).describe(at: zero) == "Focus, 13 min left")
        #expect(Pomodoro(phase: .longBreak, endsAt: zero.addingTimeInterval(0.01), completed: 4).describe(at: zero) == "Long break, 1 min left")
    }
}

@Suite struct ClaudeRules {
    private func event(_ name: String, _ session: String, type: String? = nil, message: String? = nil, cwd: String = "/work/sushi-buddy") -> ClaudeEvent {
        ClaudeEvent(hookEventName: name, sessionID: session, cwd: cwd, notificationType: type, message: message)
    }

    private let minute = { (count: Double) in Date(timeIntervalSince1970: count * 60) }

    @Test func cheersOnlyAfterATurnAsLongAsTheMinimumPerSession() {
        var claude = ClaudeTracker()
        let settings = Settings()
        let result7 = claude.handle(event("UserPromptSubmit", "a"), at: minute(0), settings)
        #expect(result7 == nil)
        let result8 = claude.handle(event("UserPromptSubmit", "b"), at: minute(1), settings)
        #expect(result8 == nil)
        let result9 = claude.handle(event("Stop", "b"), at: minute(2), settings)
        #expect(result9 == nil)
        let done = claude.handle(event("Stop", "a"), at: minute(2), settings)
        #expect(done?.kind == "claudeDone")
        #expect(done?.project == "sushi-buddy")
        let result10 = claude.handle(event("Stop", "c"), at: minute(3), settings)
        #expect(result10 == nil)
        var anyLength = settings
        anyLength.claudeMinMinutes = 0
        let result11 = claude.handle(event("Stop", "c"), at: minute(3), anyLength)
        #expect(result11?.kind == "claudeDone")
        _ = claude.handle(event("UserPromptSubmit", "d"), at: minute(0), settings)
        var off = settings
        off.claudeDone = false
        let result12 = claude.handle(event("Stop", "d"), at: minute(9), off)
        #expect(result12 == nil)
        #expect(claude.lastHeard == minute(9))
    }

    @Test func needingPermissionFliesAndOtherNotificationsDoNot() {
        var claude = ClaudeTracker()
        let settings = Settings()
        let asking = claude.handle(event("Notification", "a", type: "permission_prompt", cwd: #"C:\work\app"#), at: .now, settings)
        #expect(asking?.kind == "claudeNeedsYou")
        #expect(asking?.project == "app")
        let result13 = claude.handle(event("Notification", "a", type: "idle_prompt", message: "permission"), at: .now, settings)
        #expect(result13 == nil)
        let result14 = claude.handle(event("Notification", "a", message: "Claude needs your permission to use Bash"), at: .now, settings)
        #expect(result14?.kind == "claudeNeedsYou")
        var off = settings
        off.claudeNeedsYou = false
        let result15 = claude.handle(event("Notification", "a", type: "permission_prompt"), at: .now, off)
        #expect(result15 == nil)
        #expect(ClaudeTracker.projectName(nil) == "")
    }

    @Test func decodesAHookEventAndIgnoresTheRest() throws {
        let json = Data(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/x/y","stop_hook_active":false,"background_tasks":[]}"#.utf8)
        let event = try JSONDecoder().decode(ClaudeEvent.self, from: json)
        #expect(event.hookEventName == "Stop")
        #expect(event.sessionID == "s")
    }
}

@Suite struct ListenerRules {
    private func request(_ text: String) -> HTTPRequest.Parse {
        HTTPRequest.parse(Data(text.utf8))
    }

    @Test func takesOnlyThisComputersOwnRequestsToItsRoutes() {
        let headers = ["host": "127.0.0.1:7874"]
        #expect(Listener.vet(method: "POST", target: "/claude", headers: headers, port: 7874).route == .claude)
        #expect(Listener.vet(method: "POST", target: "/fly?x=1", headers: ["host": "localhost:7874"], port: 7874).route == .fly)
        #expect(Listener.vet(method: "GET", target: "/", headers: headers, port: 7874) == (200, .hello))
        #expect(Listener.vet(method: "POST", target: "/claude", headers: headers.merging(["origin": "https://evil.example"]) { $1 }, port: 7874).status == 403)
        #expect(Listener.vet(method: "POST", target: "/claude", headers: ["host": "evil.example:7874"], port: 7874).status == 403)
        #expect(Listener.vet(method: "POST", target: "/claude", headers: [:], port: 7874).status == 403)
        #expect(Listener.vet(method: "GET", target: "/claude", headers: headers, port: 7874).status == 404)
        #expect(Listener.vet(method: "POST", target: "/delete", headers: headers, port: 7874).status == 404)
    }

    @Test func aFlyMessageComesAsJSONOrPlainTextCleanedAndCut() {
        #expect(Listener.flyMessage(Data(#"{"message": "Hi there"}"#.utf8)) == "Hi there")
        #expect(Listener.flyMessage(Data("Plain hello".utf8)) == "Plain hello")
        #expect(Listener.flyMessage(Data()) == nil)
        #expect(Listener.flyMessage(Data("{}".utf8)) == nil)
        #expect(Listener.flyMessage(Data(#"{"message": "a\nb\u0007c"}"#.utf8)) == "a b c")
        #expect(Listener.flyMessage(Data(String(repeating: "🍣", count: 200).utf8))?.unicodeScalars.count == 140)
    }

    @Test func parsesARequestOnceItIsAllThere() {
        let full = "POST /claude HTTP/1.1\r\nHost: 127.0.0.1:7874\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
        guard case .request(let parsed) = request(full) else {
            Issue.record("expected a request")
            return
        }
        #expect(parsed.method == "POST")
        #expect(parsed.target == "/claude")
        #expect(parsed.headers["content-type"] == "application/json")
        #expect(parsed.body == Data("{}".utf8))
        #expect(request(String(full.dropLast())) == .incomplete)
        #expect(request("POST /claude HTTP/1.1\r\nHost: x") == .incomplete)
        #expect(request("NONSENSE\r\n\r\n") == .malformed)
        #expect(request("POST /fly HTTP/1.1\r\nContent-Length: 999999\r\n\r\n") == .tooLarge)
        #expect(request("POST /fly HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == .malformed)
        guard case .request(let empty) = request("GET / HTTP/1.1\r\nHost: localhost:7874\r\n\r\n") else {
            Issue.record("expected a request without a body")
            return
        }
        #expect(empty.body.isEmpty)
    }
}

@Suite struct FlightRules {
    @Test(arguments: FlightPath.allCases)
    func everyPathIsBackOnTheLineWhereTheHoverStartsAndEnds(path: FlightPath) {
        for direction in [1.0, -1.0] {
            for (isFlyIn, u) in [(true, 0.0), (true, 1.0), (false, 0.0), (false, 1.0)] {
                let offset = path.offset(isFlyIn: isFlyIn, u: u, direction: direction)
                #expect(abs(offset.dx) < 1e-9 && abs(offset.dy) < 1e-9)
                let turn = offset.spin.truncatingRemainder(dividingBy: 360)
                #expect(abs(turn) < 1e-9)
            }
        }
    }

    @Test(arguments: FlightPath.allCases)
    func noPathJumpsAtTheHover(path: FlightPath) {
        let flight = Flight.preview(on: CGSize(width: 1600, height: 900), path: path)
        for edge in [flight.flyIn, flight.flyIn + flight.hover] {
            let before = flight.pose(at: edge - 1e-6).center
            let after = flight.pose(at: edge + 1e-6).center
            #expect(hypot(before.x - after.x, before.y - after.y) < 0.01)
        }
    }

    @Test(arguments: [FlightPath.loop, .bounce, .zigzag])
    func thePathsReallyLeaveTheLine(path: FlightPath) {
        let canvas = CGSize(width: 1600, height: 900)
        let flight = Flight.preview(on: canvas, path: path)
        let classic = Flight.preview(on: canvas)
        let strays = (0..<72).map { Double($0) / 10 }.contains { time in
            abs(flight.pose(at: time).center.y - classic.pose(at: time).center.y) > 20
        }
        #expect(strays)
    }

    @Test func theSushiIsPettableOnlyUnderTheMouse() {
        let flight = Flight.preview(on: CGSize(width: 900, height: 420))
        let frame = CGRect(x: 100, y: 50, width: 900, height: 420)
        let center = flight.pose(at: 3).center
        let onSushi = CGPoint(x: frame.minX + center.x, y: frame.maxY - center.y)
        #expect(FlightController.isOverSushi(onSushi, flight: flight, at: 3, in: frame))
        #expect(!FlightController.isOverSushi(CGPoint(x: onSushi.x + 120, y: onSushi.y), flight: flight, at: 3, in: frame))
    }

    @Test func aPetSpinsSquishesAndSendsHeartsThenSettles() {
        let fresh = PetReaction(pets: [1.0], time: 1.2)
        #expect(fresh.extraSpin > 0)
        #expect(fresh.squish > 1)
        #expect(fresh.hearts.count == 3)
        let settled = PetReaction(pets: [1.0], time: 3.0)
        #expect(settled.extraSpin == 720)
        #expect(settled.squish == 1)
        #expect(settled.hearts.isEmpty)
        #expect(PetReaction(pets: [5.0], time: 1.0).hearts.isEmpty)
    }

    @Test func aHeldFlightHoversUntilLetGoThenFadesItsBubbleAndLeavesWithoutAJump() {
        var flight = Flight.preview(on: CGSize(width: 1600, height: 900))
        flight.hover = .infinity
        let hovering = flight.pose(at: 60)
        #expect(abs(hovering.center.x - flight.hoverX) <= 8)
        #expect(hovering.bubble == 1)

        flight.letGo(at: 60)
        let letGo = flight.pose(at: 60)
        #expect(letGo.center == hovering.center)
        #expect(letGo.bubble == 1)
        #expect(flight.pose(at: 60.36).bubble == 0)
        let edge = flight.flyIn + flight.hover
        let before = flight.pose(at: edge - 1e-6).center
        let after = flight.pose(at: edge + 1e-6).center
        #expect(hypot(before.x - after.x, before.y - after.y) < 0.01)
        #expect(flight.pose(at: edge + flight.flyOut).center.x > 1600)
    }
}

@Suite struct TourRules {
    private let switches = Tour.steps(on: .mac, shortcut: nil).flatMap(\.switches)

    @Test func everyoneSeesTheTourOnceAtAMomentAnAutomaticFlightCouldGo() {
        #expect(Tour.startsOnItsOwn(seen: false, quiet: nil))
        #expect(!Tour.startsOnItsOwn(seen: true, quiet: nil))
        #expect(!Tour.startsOnItsOwn(seen: false, quiet: .call))
    }

    @Test func theStepsShowEveryFeatureAndEndWithWhereToFindThemAgain() throws {
        let steps = Tour.steps(on: .mac, shortcut: "⌃⌥⌘S")
        #expect(steps.map(\.id) == ["hello", "home", "shortcut", "pet", "tricks", "onTheirOwn", "quiet", "claude", "bye"])
        #expect(steps[2].text.contains("⌃⌥⌘S"))
        #expect(Tour.steps(on: .mac, shortcut: nil)[2].text.contains("Settings"))
        #expect(steps.filter(\.showsLoop).map(\.id) == ["tricks"])
        #expect(try #require(steps.first { $0.id == "claude" }).copies == Tour.claudeInstall)
        #expect(switches.map(\.key) == ["petting", "sound", "autoMotivateSeconds", "breakReminderMinutes", "welcomeBack"])
        #expect(try #require(steps.last).text.contains("Settings"))
        #expect(Tour.steps(on: .windows, shortcut: nil)[1].text.contains("tray"))
    }

    @Test func aSwitchTurnsOnWhatItOffersAndOffBackToOff() {
        let offered: [String: AnyHashable] = ["petting": true, "sound": "chime", "autoMotivateSeconds": 3600, "breakReminderMinutes": 60, "welcomeBack": true]
        let off: [String: AnyHashable] = ["petting": false, "sound": "off", "autoMotivateSeconds": 0, "breakReminderMinutes": 0, "welcomeBack": false]
        for toggle in switches {
            var settings = Settings()
            toggle.turn(&settings, false)
            #expect(!toggle.isOn(settings))
            #expect(settings.values[toggle.key] as? AnyHashable == off[toggle.key])
            toggle.turn(&settings, true)
            #expect(toggle.isOn(settings))
            #expect(settings.values[toggle.key] as? AnyHashable == offered[toggle.key])
        }
    }

    @Test func aChoiceMadeInSettingsCountsAsOnAndIsKept() throws {
        var settings = Settings()
        settings.autoMotivateSeconds = 7200
        settings.sound = "whirr"
        for key in ["autoMotivateSeconds", "sound"] {
            let toggle = try #require(switches.first { $0.key == key })
            #expect(toggle.isOn(settings))
            toggle.turn(&settings, true)
        }
        #expect(settings.autoMotivateSeconds == 7200)
        #expect(settings.sound == "whirr")
    }

    @Test func theSushiWaitsByItsIconWithTheBubbleOnTheRoomierSide() {
        let underMenuBar = CGRect(x: 0, y: 33, width: 1512, height: 916)
        #expect(Tour.place(anchor: CGPoint(x: 995, y: 16), in: underMenuBar)
            == Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true))
        let aboveTaskbar = CGRect(x: 0, y: 0, width: 1920, height: 1032)
        #expect(Tour.place(anchor: CGPoint(x: 1850, y: 1056), in: aboveTaskbar)
            == Tour.Spot(x: 1812, y: 924, bubbleOnLeft: true, bubbleBelow: false))
        let besideLeftTaskbar = CGRect(x: 48, y: 0, width: 1872, height: 1080)
        #expect(Tour.place(anchor: CGPoint(x: 24, y: 1000), in: besideLeftTaskbar)
            == Tour.Spot(x: 156, y: 972, bubbleOnLeft: false, bubbleBelow: false))
    }

    @Test func theBubbleSitsBesideTheSushiNotOverIt() {
        let spots = [
            Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true),
            Tour.Spot(x: 156, y: 972, bubbleOnLeft: false, bubbleBelow: false),
        ]
        #expect(spots.map(Tour.bubbleCorner) == [CGPoint(x: 896, y: 69), CGPoint(x: 255, y: 1044)])
    }

    @Test func theTourTakesClicksOnlyOnTheSushiAndTheShownBubble() {
        let sushi = CGPoint(x: 995, y: 141)
        let bubble = CGRect(x: 500, y: 69, width: 380, height: 200)
        #expect(Tour.isOver(CGPoint(x: 1010, y: 160), sushi: sushi, bubble: bubble))
        #expect(Tour.isOver(CGPoint(x: 600, y: 250), sushi: sushi, bubble: bubble))
        #expect(!Tour.isOver(CGPoint(x: 300, y: 600), sushi: sushi, bubble: bubble))
        #expect(!Tour.isOver(CGPoint(x: 600, y: 250), sushi: sushi, bubble: .null))
    }

    @Test func theLoopDemoLeavesTheLineAndComesBackWhereItStarted() {
        var flight = Flight.preview(on: CGSize(width: 1600, height: 900))
        flight.hover = .infinity
        for time in [10.0, 12.0] {
            let looping = Tour.pose(flight, at: time, loops: [10]).center
            let plain = flight.pose(at: time).center
            #expect(hypot(looping.x - plain.x, looping.y - plain.y) < 0.01)
        }
        let midLoop = Tour.pose(flight, at: 11, loops: [10]).center
        #expect(abs(midLoop.y - flight.pose(at: 11).center.y) > 40)
    }
}

@MainActor
@Suite struct TourModelRules {
    @Test func nextWalksTheStepsLoopsOnTricksAndDoneLetsGoOnce() {
        let model = TourModel(
            steps: Tour.steps(on: .mac, shortcut: nil),
            spot: Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true),
            canvas: CGSize(width: 1512, height: 982)
        )
        var finished = 0
        model.onFinish = { finished += 1 }
        for _ in 0..<4 { model.next() }
        #expect(model.step.id == "tricks")
        #expect(model.loops.count == 1)
        while !model.isLast { model.next() }
        #expect(!model.isLeaving)
        model.next()
        #expect(model.isLeaving)
        model.next()
        model.finish()
        #expect(finished == 1)
        #expect(model.step.id == "bye")
    }

    @Test func backReturnsOneStepLoopsAgainOnTricksAndStopsAtTheFirst() {
        let model = TourModel(
            steps: Tour.steps(on: .mac, shortcut: nil),
            spot: Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true),
            canvas: CGSize(width: 1512, height: 982)
        )
        #expect(model.isFirst)
        model.back()
        #expect(model.index == 0)
        for _ in 0..<5 { model.next() }
        #expect(model.step.id == "onTheirOwn")
        model.back()
        #expect(model.step.id == "tricks")
        #expect(model.loops.count == 2)
        #expect(!model.isFirst)
        while !model.isFirst { model.back() }
        #expect(model.step.id == "hello")
        model.back()
        #expect(model.index == 0)
    }

    @Test func backDoesNothingOnceTheSushiIsLeaving() {
        let model = TourModel(
            steps: Tour.steps(on: .mac, shortcut: nil),
            spot: Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true),
            canvas: CGSize(width: 1512, height: 982)
        )
        model.next()
        model.next()
        model.finish()
        model.back()
        #expect(model.step.id == "shortcut")
    }

    @Test func skippingLetsGoFromAnyStep() {
        let model = TourModel(
            steps: Tour.steps(on: .mac, shortcut: nil),
            spot: Tour.Spot(x: 995, y: 141, bubbleOnLeft: true, bubbleBelow: true),
            canvas: CGSize(width: 1512, height: 982)
        )
        model.next()
        model.finish()
        #expect(model.isLeaving)
        model.next()
        #expect(model.step.id == "home")
    }
}
