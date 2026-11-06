import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO

/// What macOS says about the moment, for the quiet rules. None of it needs a permission
/// except Focus, which asks once (see FocusStatus).
@MainActor
enum SystemSignals {
    /// Seconds since the last key press, click or mouse move.
    static var idleSeconds: TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    static var isLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Some app is recording from a microphone: macOS 14 says so per process.
    static var microphoneInUse: Bool {
        audioObjects(kAudioHardwarePropertyProcessObjectList).contains { process in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
        }
    }

    static var cameraInUse: Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueSize, &value)
            return status == noErr && value != 0
        }
    }

    /// The app in front fills a whole display: a full-screen app, a slideshow, a shared screen in a call app.
    static var isPresenting: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let screens = displays.map(CGDisplayBounds)
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == front,
                  (window[kCGWindowLayer as String] as? Int ?? -1) >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return screens.contains(frame)
        }
    }

    static func quietSignals(awayMinutes: Int) -> QuietSignals {
        QuietSignals(
            away: Quiet.isAway(idleSeconds: idleSeconds, locked: isLocked, awayMinutes: awayMinutes),
            focus: FocusStatus.isFocused,
            call: microphoneInUse || cameraInUse,
            presenting: isPresenting
        )
    }

    /// One line per signal, for `--status` and Settings.
    static func describe(awayMinutes: Int) -> [String] {
        [
            "Focus: \(FocusStatus.isFocused ? "on" : "off") (access \(FocusStatus.authorization == .authorized ? "allowed" : "not allowed"))",
            "Idle: \(Int(idleSeconds)) s, screen \(isLocked ? "locked" : "unlocked") (away after \(awayMinutes) min)",
            "Microphone: \(microphoneInUse ? "in use" : "not in use"), camera: \(cameraInUse ? "in use" : "not in use")",
            "Full-screen app in front: \(isPresenting ? "yes" : "no")",
        ]
    }

    private static func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }
}
