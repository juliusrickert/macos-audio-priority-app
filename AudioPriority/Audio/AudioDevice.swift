import CoreAudio

/// Which default-device slot we are managing.
enum Direction: String, CaseIterable, Codable {
    case output
    case input

    var displayName: String {
        switch self {
        case .output: return "Output"
        case .input: return "Input"
        }
    }
}

/// A snapshot of an audio device currently present on the system.
///
/// `uid` is the stable identifier (`kAudioDevicePropertyDeviceUID`) that
/// survives reconnect/reboot/rename. `id` is the transient `AudioDeviceID`
/// and must never be persisted.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool

    /// Does this device participate in the given direction's list?
    func participates(in direction: Direction) -> Bool {
        switch direction {
        case .output: return hasOutput
        case .input: return hasInput
        }
    }
}
