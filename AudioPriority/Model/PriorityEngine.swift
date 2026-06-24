import Foundation

/// Decides which device should be the default for each direction and applies
/// the decision. The pure resolution logic (`desiredDefault`) is static and
/// unit-tested with mock data.
final class PriorityEngine {

    private let manager: AudioDeviceManager
    private let store: PriorityStore

    /// When true, `reconcile()` is a no-op (user paused auto-switching).
    var isPaused = false

    init(manager: AudioDeviceManager, store: PriorityStore) {
        self.manager = manager
        self.store = store
    }

    /// The UID of the highest-priority device that is currently available and
    /// enabled, or nil if no eligible prioritized device is present.
    static func desiredDefault(
        priority: [StoredDevice],
        available: [AudioDevice],
        direction: Direction
    ) -> String? {
        let presentUIDs = Set(
            available.filter { $0.participates(in: direction) }.map(\.uid))
        return priority.first { $0.enabled && presentUIDs.contains($0.uid) }?.uid
    }

    /// For each direction, promote the highest-priority available device to be
    /// the system default if it isn't already. Idempotent: only writes when the
    /// desired default differs from the current one, which avoids feedback loops
    /// from the change listener.
    func reconcile() {
        guard !isPaused else { return }
        let available = manager.currentDevices()

        for direction in Direction.allCases {
            guard let desired = Self.desiredDefault(
                priority: store.list(for: direction),
                available: available,
                direction: direction)
            else { continue }

            let current = manager.defaultDevice(for: direction)?.uid
            if current != desired {
                manager.setDefault(uid: desired, for: direction)
            }
        }
    }
}
