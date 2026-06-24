import CoreAudio
import Foundation

/// The single point of contact with the CoreAudio C API.
///
/// Responsibilities: enumerate devices, resolve stable UIDs, classify
/// input/output, get/set the system default device, and host a coalesced
/// device-change listener. Nothing else in the app touches CoreAudio.
final class AudioDeviceManager {

    // MARK: Enumeration

    /// All audio devices currently present on the system.
    func currentDevices() -> [AudioDevice] {
        let deviceIDs = systemDeviceIDs()
        return deviceIDs.compactMap { makeDevice(from: $0) }
    }

    private func systemDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr
        else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr
        else { return [] }

        return ids
    }

    private func makeDevice(from id: AudioDeviceID) -> AudioDevice? {
        guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
        let hasInput = hasStreams(id, scope: kAudioObjectPropertyScopeInput)
        let hasOutput = hasStreams(id, scope: kAudioObjectPropertyScopeOutput)
        // Ignore devices that are neither input nor output.
        guard hasInput || hasOutput else { return nil }
        return AudioDevice(id: id, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput)
    }

    // MARK: Defaults

    func defaultDevice(for direction: Direction) -> AudioDevice? {
        var address = defaultDeviceAddress(for: direction)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return makeDevice(from: deviceID)
    }

    /// Set the system default device for `direction` to the device with `uid`.
    /// Returns false if no present device matches the UID or the set fails.
    @discardableResult
    func setDefault(uid: String, for direction: Direction) -> Bool {
        guard let device = currentDevices().first(where: { $0.uid == uid }) else { return false }
        var address = defaultDeviceAddress(for: direction)
        var deviceID = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceID) == noErr
    }

    private func defaultDeviceAddress(for direction: Direction) -> AudioObjectPropertyAddress {
        let selector = direction == .output
            ? kAudioHardwarePropertyDefaultOutputDevice
            : kAudioHardwarePropertyDefaultInputDevice
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Change listener

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var pendingCoalesce = false
    private var followUpItems: [DispatchWorkItem] = []

    /// Bluetooth audio devices (AirPods) are published to CoreAudio a few seconds
    /// *after* the connect event, so the immediate rescan can run before the
    /// device exists. Re-scan again at these delays to catch the late arrival.
    private let followUpDelays: [TimeInterval] = [1.5, 3.0]

    /// Properties whose changes should re-run reconciliation:
    /// - the device set (connect/disconnect), and
    /// - the current default input/output. macOS forcibly changes the default
    ///   when a device like AirPods connects — *after* and separately from the
    ///   device-set change — so we must observe it to re-assert priority.
    private func listenedAddresses() -> [AudioObjectPropertyAddress] {
        [kAudioHardwarePropertyDevices,
         kAudioHardwarePropertyDefaultInputDevice,
         kAudioHardwarePropertyDefaultOutputDevice].map {
            AudioObjectPropertyAddress(
                mSelector: $0,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        }
    }

    /// Begin listening for device-set and default-device changes. `onChange` is
    /// invoked on the main queue, coalesced so a burst of CoreAudio callbacks
    /// (across all observed properties) fires `onChange` once per run-loop turn.
    func startListening(onChange: @escaping () -> Void) {
        stopListening()
        // One block ignores its (objectID, addresses) args, so it serves every
        // observed property.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.pendingCoalesce else { return }
                self.pendingCoalesce = true
                DispatchQueue.main.async {
                    self.pendingCoalesce = false
                    onChange()
                    self.scheduleFollowUps(onChange)
                }
            }
        }
        listenerBlock = block
        for var address in listenedAddresses() {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
    }

    /// Re-run `onChange` after each follow-up delay. Any pending follow-ups from a
    /// previous burst are cancelled first, so overlapping bursts don't stack.
    private func scheduleFollowUps(_ onChange: @escaping () -> Void) {
        followUpItems.forEach { $0.cancel() }
        followUpItems = followUpDelays.map { delay in
            let item = DispatchWorkItem(block: onChange)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    }

    func stopListening() {
        followUpItems.forEach { $0.cancel() }
        followUpItems = []
        guard let block = listenerBlock else { return }
        for var address in listenedAddresses() {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        listenerBlock = nil
    }

    deinit { stopListening() }

    // MARK: Property helpers

    private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
}
