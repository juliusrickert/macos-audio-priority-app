import Testing
import Foundation
import CoreAudio
@testable import AudioPriority

private func device(_ uid: String, id: AudioDeviceID, output: Bool, input: Bool) -> AudioDevice {
    AudioDevice(id: id, uid: uid, name: uid, hasInput: input, hasOutput: output)
}

/// A throwaway UserDefaults suite so tests don't touch the real domain.
private func freshDefaults() -> UserDefaults {
    let suite = "PriorityStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

struct PriorityStoreTests {

    @Test func mergeAppendsNewDevicesAtBottom() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [
            device("Speakers", id: 1, output: true, input: false),
            device("HDMI", id: 2, output: true, input: false),
        ])
        #expect(store.list(for: .output).map(\.uid) == ["Speakers", "HDMI"])

        // A later device joins at the end; existing order is preserved.
        store.merge(currentDevices: [
            device("Speakers", id: 1, output: true, input: false),
            device("USB", id: 3, output: true, input: false),
        ])
        #expect(store.list(for: .output).map(\.uid) == ["Speakers", "HDMI", "USB"])
    }

    @Test func mergeKeepsDisconnectedDevices() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [device("USB", id: 1, output: true, input: false)])
        // Next scan: USB gone, only built-in present. USB must remain remembered.
        store.merge(currentDevices: [device("BuiltIn", id: 2, output: true, input: false)])
        #expect(store.list(for: .output).map(\.uid) == ["USB", "BuiltIn"])
    }

    @Test func classifiesIntoBothLists() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [
            device("Interface", id: 1, output: true, input: true),
        ])
        #expect(store.list(for: .output).map(\.uid) == ["Interface"])
        #expect(store.list(for: .input).map(\.uid) == ["Interface"])
    }

    @Test func reorderMovesRows() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [
            device("A", id: 1, output: true, input: false),
            device("B", id: 2, output: true, input: false),
            device("C", id: 3, output: true, input: false),
        ])
        store.reorder(.output, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.list(for: .output).map(\.uid) == ["C", "A", "B"])
    }

    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let store = PriorityStore(defaults: defaults)
        store.merge(currentDevices: [device("A", id: 1, output: true, input: false)])
        store.reorder(.output, fromOffsets: IndexSet(integer: 0), toOffset: 0)

        let reloaded = PriorityStore(defaults: defaults)
        #expect(reloaded.list(for: .output).map(\.uid) == ["A"])
    }

    @Test func removeForgetsDevice() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [
            device("A", id: 1, output: true, input: false),
            device("B", id: 2, output: true, input: false),
        ])
        store.remove(.output, uid: "A")
        #expect(store.list(for: .output).map(\.uid) == ["B"])
    }

    @Test func decodesLegacyJSONWithoutEnabledAsTrue() {
        // JSON written before `enabled` existed must load with everything enabled.
        let defaults = freshDefaults()
        let legacy = #"{"output":[{"uid":"A","lastSeenName":"A"}],"input":[]}"#
        defaults.set(Data(legacy.utf8), forKey: "priorityLists.v1")

        let store = PriorityStore(defaults: defaults)
        #expect(store.list(for: .output).first?.uid == "A")
        #expect(store.list(for: .output).first?.enabled == true)
    }

    @Test func setEnabledPersistsAndFlips() {
        let defaults = freshDefaults()
        let store = PriorityStore(defaults: defaults)
        store.merge(currentDevices: [device("A", id: 1, output: false, input: true)])
        store.setEnabled(false, direction: .input, uid: "A")

        let reloaded = PriorityStore(defaults: defaults)
        #expect(reloaded.list(for: .input).first?.enabled == false)
    }

    @Test func mergePreservesEnabledFlag() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [device("A", id: 1, output: false, input: true)])
        store.setEnabled(false, direction: .input, uid: "A")
        // Reconnect the same device with an updated name.
        store.merge(currentDevices: [
            AudioDevice(id: 1, uid: "A", name: "A renamed", hasInput: true, hasOutput: false),
        ])
        let entry = store.list(for: .input).first
        #expect(entry?.enabled == false)
        #expect(entry?.lastSeenName == "A renamed")
    }

    @Test func reorderPreservesEnabledFlag() {
        let store = PriorityStore(defaults: freshDefaults())
        store.merge(currentDevices: [
            device("A", id: 1, output: true, input: false),
            device("B", id: 2, output: true, input: false),
            device("C", id: 3, output: true, input: false),
        ])
        store.setEnabled(false, direction: .output, uid: "B")
        store.reorder(.output, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(store.list(for: .output).map(\.uid) == ["B", "A", "C"])
        #expect(store.list(for: .output).first(where: { $0.uid == "B" })?.enabled == false)
    }
}
