import SwiftUI

/// The priority-management window. Two drag-to-reorder lists (Output, Input).
/// Disconnected-but-remembered devices appear greyed with a tag and can be
/// forgotten via the context menu.
struct PriorityWindow: View {
    @ObservedObject var store: PriorityStore
    /// UIDs of devices currently present, by direction. Drives connected state.
    let presentUIDs: [Direction: Set<String>]
    /// Called after any reorder/remove so the engine can re-apply priorities.
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Device Priority")
                .font(.title2).bold()
            Text("Drag to reorder. The highest device that is connected becomes the default.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                listColumn(for: .output)
                listColumn(for: .input)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
    }

    private func listColumn(for direction: Direction) -> some View {
        let present = presentUIDs[direction] ?? []
        let devices = store.list(for: direction)
        return VStack(alignment: .leading, spacing: 6) {
            Text(direction.displayName)
                .font(.headline)
            List {
                ForEach(devices) { device in
                    row(device, connected: present.contains(device.uid), direction: direction)
                }
                .onMove { source, destination in
                    store.reorder(direction, fromOffsets: source, toOffset: destination)
                    onChange()
                }
            }
            .frame(maxHeight: .infinity)
            if devices.isEmpty {
                Text("No devices seen yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ device: StoredDevice, connected: Bool, direction: Direction) -> some View {
        // A device is eligible to become the default only when enabled; an
        // excluded device is dimmed regardless of whether it's connected.
        let active = connected && device.enabled
        return HStack {
            Toggle("", isOn: Binding(
                get: { device.enabled },
                set: { store.setEnabled($0, direction: direction, uid: device.uid); onChange() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Eligible as default \(direction.displayName.lowercased())")

            Image(systemName: direction == .output ? "speaker.wave.2.fill" : "mic.fill")
                .foregroundStyle(active ? Color.accentColor : .secondary)
            Text(device.lastSeenName)
                .foregroundStyle(active ? .primary : .secondary)
                .strikethrough(!device.enabled)
            Spacer()
            if !device.enabled {
                tag("excluded")
            } else if !connected {
                tag("disconnected")
            }
        }
        .contextMenu {
            Button(device.enabled ? "Exclude from \(direction.displayName)"
                                  : "Include in \(direction.displayName)") {
                store.setEnabled(!device.enabled, direction: direction, uid: device.uid)
                onChange()
            }
            Button("Forget Device", role: .destructive) {
                store.remove(direction, uid: device.uid)
                onChange()
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
