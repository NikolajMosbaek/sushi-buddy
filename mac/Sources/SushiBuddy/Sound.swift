import AppKit

/// The optional flight sounds in Resources (made by Art/make-sounds.py): a chime as the
/// bubble pops up, or a propeller whirr exactly as long as a flight.
@MainActor
enum Sound {
    /// Held while playing; a released NSSound stops.
    private static var playing: [NSSound] = []

    static func accompany(_ flight: Flight, with choice: String) {
        switch choice {
        case "chime": play("chime", after: flight.flyIn - 0.3)
        case "whirr": play("whirr")
        default: break
        }
    }

    static func play(_ name: String, after delay: TimeInterval = 0) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        sound.volume = 0.5
        playing.append(sound)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            sound.play()
            try? await Task.sleep(for: .seconds(sound.duration + 0.5))
            playing.removeAll { $0 === sound }
        }
    }
}
