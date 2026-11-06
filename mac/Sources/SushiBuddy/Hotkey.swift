import Carbon.HIToolbox

/// A system-wide shortcut for "Motivate me". Carbon's hot keys need no Accessibility permission.
@MainActor
final class Hotkey {
    struct Preset {
        let id: String
        let label: String
        let keyCode: Int
        let modifiers: Int
    }

    static let presets = [
        Preset(id: "off", label: "Off", keyCode: 0, modifiers: 0),
        Preset(id: "control+option+command+s", label: "⌃⌥⌘S", keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey | cmdKey),
        Preset(id: "control+option+s", label: "⌃⌥S", keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey),
        Preset(id: "control+option+command+m", label: "⌃⌥⌘M", keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey | cmdKey),
    ]

    private let action: @MainActor () -> Void
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Registers the preset, replacing the one before. Returns why it couldn't, or nil.
    func register(_ id: String) -> String? {
        unregister()
        guard let preset = Self.presets.first(where: { $0.id == id }), preset.id != "off" else { return nil }
        installHandler()
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5355_5348), id: 1)  // "SUSH"
        let status = RegisterEventHotKey(
            UInt32(preset.keyCode), UInt32(preset.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else {
            return "\(preset.label) is taken by another app; pick another."
        }
        registration = reference
        return nil
    }

    private func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &type, me, &handler)
    }
}
