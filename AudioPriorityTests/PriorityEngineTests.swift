import Testing
import CoreAudio
@testable import AudioPriority

private func device(_ uid: String, id: AudioDeviceID, output: Bool, input: Bool) -> AudioDevice {
    AudioDevice(id: id, uid: uid, name: uid, hasInput: input, hasOutput: output)
}

private func stored(_ uids: [String]) -> [StoredDevice] {
    uids.map { StoredDevice(uid: $0, lastSeenName: $0) }
}

private func disabled(_ uid: String) -> StoredDevice {
    StoredDevice(uid: uid, lastSeenName: uid, enabled: false)
}

struct PriorityEngineTests {

    @Test func picksHighestAvailable() {
        let priority = stored(["A", "B", "BuiltIn"])
        let available = [
            device("B", id: 2, output: true, input: false),
            device("BuiltIn", id: 3, output: true, input: false),
        ]
        let desired = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .output)
        #expect(desired == "B")
    }

    @Test func fallsBackWhenTopUnavailable() {
        let priority = stored(["A", "B", "BuiltIn"])
        let available = [device("BuiltIn", id: 3, output: true, input: false)]
        let desired = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .output)
        #expect(desired == "BuiltIn")
    }

    @Test func nilWhenNothingAvailable() {
        let priority = stored(["A", "B"])
        let desired = PriorityEngine.desiredDefault(
            priority: priority, available: [], direction: .output)
        #expect(desired == nil)
    }

    @Test func skipsDisabledDevice() {
        // AirPods ranked top but excluded from input → the next enabled mic wins.
        let priority = [disabled("AirPods"), stored(["BuiltInMic"])[0]]
        let available = [
            device("AirPods", id: 1, output: false, input: true),
            device("BuiltInMic", id: 2, output: false, input: true),
        ]
        let desired = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .input)
        #expect(desired == "BuiltInMic")
    }

    @Test func disabledTopStillExcludedWhenSoleOption() {
        // Only a disabled device is present → no eligible default.
        let priority = [disabled("AirPods")]
        let available = [device("AirPods", id: 1, output: false, input: true)]
        let desired = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .input)
        #expect(desired == nil)
    }

    @Test func enabledDefaultsTrue() {
        #expect(StoredDevice(uid: "A", lastSeenName: "A").enabled == true)
    }

    @Test func respectsDirectionScope() {
        // "Mic" is input-only; it must not be chosen for the output list.
        let priority = stored(["Mic", "Speakers"])
        let available = [
            device("Mic", id: 1, output: false, input: true),
            device("Speakers", id: 2, output: true, input: false),
        ]
        let outputChoice = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .output)
        #expect(outputChoice == "Speakers")

        let inputChoice = PriorityEngine.desiredDefault(
            priority: priority, available: available, direction: .input)
        #expect(inputChoice == "Mic")
    }
}
