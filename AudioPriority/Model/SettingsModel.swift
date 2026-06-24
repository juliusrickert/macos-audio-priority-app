import AppKit
import Combine
import ServiceManagement

/// Single source of truth for the two global toggles (pause auto-switching,
/// launch at login) so the menu-bar dropdown and the Priority Window stay in
/// sync. Both surfaces read and write this object; changes made in one are
/// reflected in the other (the window via `@Published`, the menu via the
/// `onChange` hook that re-renders it).
final class SettingsModel: ObservableObject {

    private let engine: PriorityEngine
    private let defaults: UserDefaults
    private let pauseKey = "autoSwitchPaused"

    /// Called after any change so the AppKit menu can refresh its checkmarks.
    var onChange: () -> Void = {}

    /// Auto-switching paused. Persisted to UserDefaults and mirrored into the
    /// engine (whose `reconcile()` is a no-op while paused).
    @Published var isPaused: Bool {
        didSet {
            guard oldValue != isPaused else { return }
            engine.isPaused = isPaused
            defaults.set(isPaused, forKey: pauseKey)
            if !isPaused { engine.reconcile() }
            onChange()
        }
    }

    /// Launch the app at login. Backed by `SMAppService`, which owns the real
    /// state — we mirror it here for binding and re-read after every mutation
    /// so the toggle reflects what actually happened.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin, !suppressApply else { return }
            apply(launchAtLogin)
        }
    }

    init(engine: PriorityEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults

        let paused = defaults.bool(forKey: pauseKey)
        self.isPaused = paused
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)

        // The stored `isPaused` didSet doesn't run during init, so push the
        // loaded value into the engine explicitly.
        engine.isPaused = paused
    }

    /// Re-sync `launchAtLogin` from the system, since the login-items state can
    /// change outside the app (e.g. via System Settings). Call when a surface
    /// that displays the toggle appears.
    func refreshFromSystem() {
        setLaunchAtLoginSilently(SMAppService.mainApp.status == .enabled)
        onChange()
    }

    // MARK: - Private

    private func apply(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        // Reflect whatever the system now reports, then refresh the menu.
        setLaunchAtLoginSilently(SMAppService.mainApp.status == .enabled)
        onChange()
    }

    /// Update the published value without running the register/unregister side
    /// effect, used when mirroring the system's actual state back into the model.
    private func setLaunchAtLoginSilently(_ value: Bool) {
        guard launchAtLogin != value else { return }
        suppressApply = true
        launchAtLogin = value
        suppressApply = false
    }

    /// When true, `launchAtLogin`'s didSet skips the side effect (we're only
    /// mirroring system state, not requesting a change).
    private var suppressApply = false
}
