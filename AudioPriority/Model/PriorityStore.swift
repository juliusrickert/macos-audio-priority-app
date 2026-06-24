import Foundation

/// A device remembered in a priority list. Persisted by stable UID; the name
/// is cached only for display when the device is disconnected.
///
/// `enabled` is per-list-entry, so a device that lives in both lists can be
/// enabled for output while excluded from input (e.g. AirPods: keep as a speaker,
/// never as the default mic).
struct StoredDevice: Codable, Identifiable, Hashable {
    let uid: String
    var lastSeenName: String
    var enabled: Bool

    var id: String { uid }

    init(uid: String, lastSeenName: String, enabled: Bool = true) {
        self.uid = uid
        self.lastSeenName = lastSeenName
        self.enabled = enabled
    }

    // Decode `enabled` as true when absent so priority lists persisted before
    // this field (key "priorityLists.v1") keep loading with everything enabled.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        lastSeenName = try c.decode(String.self, forKey: .lastSeenName)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Persists the two ordered priority lists (output, input) and merges in newly
/// seen devices. No hardware dependency — fully unit-testable.
final class PriorityStore: ObservableObject {

    @Published private(set) var output: [StoredDevice] = []
    @Published private(set) var input: [StoredDevice] = []

    private let defaults: UserDefaults
    private let key = "priorityLists.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Access

    func list(for direction: Direction) -> [StoredDevice] {
        direction == .output ? output : input
    }

    // MARK: Mutation

    /// Reflect the set of currently-present devices: append any device not yet
    /// known to the relevant list(s) (at the bottom = lowest priority), and
    /// refresh the cached name of known devices. Disconnected devices are kept.
    func merge(currentDevices devices: [AudioDevice]) {
        for direction in Direction.allCases {
            var list = list(for: direction)
            for device in devices where device.participates(in: direction) {
                if let idx = list.firstIndex(where: { $0.uid == device.uid }) {
                    list[idx].lastSeenName = device.name
                } else {
                    list.append(StoredDevice(uid: device.uid, lastSeenName: device.name))
                }
            }
            set(list, for: direction)
        }
        save()
    }

    /// Move rows within a direction's list (drag-to-reorder from SwiftUI).
    func reorder(_ direction: Direction, fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = list(for: direction)
        list.move(fromOffsets: source, toOffset: destination)
        set(list, for: direction)
        save()
    }

    /// Include or exclude a device from being chosen as the default for a
    /// direction, without changing its position in the list.
    func setEnabled(_ enabled: Bool, direction: Direction, uid: String) {
        var list = list(for: direction)
        guard let idx = list.firstIndex(where: { $0.uid == uid }) else { return }
        list[idx].enabled = enabled
        set(list, for: direction)
        save()
    }

    /// Forget a remembered (typically disconnected) device.
    func remove(_ direction: Direction, uid: String) {
        var list = list(for: direction)
        list.removeAll { $0.uid == uid }
        set(list, for: direction)
        save()
    }

    private func set(_ list: [StoredDevice], for direction: Direction) {
        if direction == .output { output = list } else { input = list }
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var output: [StoredDevice]
        var input: [StoredDevice]
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        output = decoded.output
        input = decoded.input
    }

    private func save() {
        let persisted = Persisted(output: output, input: input)
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: key)
        }
    }
}
