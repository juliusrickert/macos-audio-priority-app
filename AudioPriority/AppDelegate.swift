import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let manager = AudioDeviceManager()
    private let store = PriorityStore()
    private lazy var engine = PriorityEngine(manager: manager, store: store)

    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    /// UIDs present per direction, republished to the window after each scan.
    private let presentModel = PresentDevicesModel()

    private let pauseKey = "autoSwitchPaused"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.isPaused = UserDefaults.standard.bool(forKey: pauseKey)

        setupStatusItem()

        // Initial scan + reconcile, then listen for changes.
        rescan()
        manager.startListening { [weak self] in self?.rescan() }

        showWindow(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    // MARK: Core flow

    /// Re-read devices, merge into the store, refresh UI state, reconcile.
    private func rescan() {
        let devices = manager.currentDevices()
        store.merge(currentDevices: devices)
        presentModel.update(from: devices)
        engine.reconcile()
        refreshMenu()
    }

    // MARK: Status item & menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "Audio Priority")
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let out = manager.defaultDevice(for: .output)?.name ?? "—"
        let mic = manager.defaultDevice(for: .input)?.name ?? "—"
        menu.addItem(disabledItem("Output: \(out)"))
        menu.addItem(disabledItem("Input: \(mic)"))
        menu.addItem(.separator())

        menu.addItem(withTitle: "Open Priority Window…",
                     action: #selector(showWindow(_:)), keyEquivalent: "")

        let pause = NSMenuItem(title: "Pause Auto-Switching",
                               action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.state = engine.isPaused ? .on : .off
        menu.addItem(pause)

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        // Items above target the AppDelegate (their selectors live here).
        for item in menu.items where item.action != nil && !item.isSeparatorItem {
            item.target = self
        }

        // Quit targets NSApp, not the delegate — terminate(_:) is an
        // NSApplication method, so it must be added AFTER the target loop.
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AudioPriority",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func showWindow(_ sender: Any?) {
        if window == nil {
            let view = PriorityWindowContainer(store: store, present: presentModel) { [weak self] in
                self?.engine.reconcile()
                self?.refreshMenu()
            }
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "AudioPriority"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 600, height: 420))
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        engine.isPaused.toggle()
        UserDefaults.standard.set(engine.isPaused, forKey: pauseKey)
        if !engine.isPaused { engine.reconcile() }
        refreshMenu()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshMenu()
    }
}

/// Observable mirror of which device UIDs are present, per direction, so the
/// SwiftUI window updates connected/disconnected state without touching CoreAudio.
final class PresentDevicesModel: ObservableObject {
    @Published var byDirection: [Direction: Set<String>] = [:]

    func update(from devices: [AudioDevice]) {
        var map: [Direction: Set<String>] = [:]
        for direction in Direction.allCases {
            map[direction] = Set(
                devices.filter { $0.participates(in: direction) }.map(\.uid))
        }
        byDirection = map
    }
}

/// Bridges the AppKit-owned models into the SwiftUI view tree.
private struct PriorityWindowContainer: View {
    @ObservedObject var store: PriorityStore
    @ObservedObject var present: PresentDevicesModel
    let onChange: () -> Void

    var body: some View {
        PriorityWindow(store: store, presentUIDs: present.byDirection, onChange: onChange)
    }
}
