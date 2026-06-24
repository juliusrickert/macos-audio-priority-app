# AudioPriority

A lightweight macOS menu-bar app that automatically switches your default audio
**output** and **input** devices according to a priority list you control.

Plug in your USB interface and it becomes the default. Connect AirPods and they
take over output — while your good mic stays the default input. Unplug a device
and macOS falls back to the next-highest-priority device that's still connected.
No more diving into System Settings every time you dock and undock.

## Features

- **Per-direction priority lists** — separate, ordered lists for output and input.
- **Per-entry enable/disable** — a device can live in both lists but be enabled
  for output and excluded as a mic (e.g. keep AirPods as speakers, never as the
  default microphone).
- **Stable identity** — devices are remembered by their CoreAudio UID, so the
  priority order survives reconnects, reboots, and renames.
- **Automatic reconciliation** — listens for device changes and promotes the
  highest-priority available device. Idempotent writes avoid feedback loops.
- **Pause auto-switching** — toggle from the menu when you want manual control.
- **Launch at Login** — registered via `SMAppService`.
- **Menu-bar agent** — no Dock icon (`LSUIElement`), stays out of your way.

## Requirements

- macOS (Apple's `SMAppService` / CoreAudio APIs)
- Xcode (to build)

## Install

```sh
./install.sh          # build (Release) + install to /Applications + launch
./install.sh --no-run # build + install only
```

The app is installed to `/Applications/AudioPriority.app`. A stable install
location matters: "Launch at Login" registers the *running* bundle's path, so it
must not live in Xcode's `DerivedData`.

## Usage

The app lives in your menu bar (slider icon). The menu shows the current default
output and input, and lets you:

- **Open Priority Window…** — reorder devices and toggle each entry per direction.
- **Pause Auto-Switching** — stop automatic reconciliation.
- **Launch at Login** — register/unregister the login item.
- **Quit**.

## Architecture

- `AudioDeviceManager` — the single point of contact with the CoreAudio C API
  (enumerate devices, resolve UIDs, get/set defaults, host the change listener).
- `PriorityEngine` — decides the desired default per direction and applies it.
  The pure resolution logic (`desiredDefault`) is static and unit-tested.
- `PriorityStore` — persists the two ordered priority lists and merges in newly
  seen devices. No hardware dependency, fully unit-testable.
- `AppDelegate` — owns the status item, menu, and the SwiftUI priority window.
  Drives everything programmatically (`.accessory` activation policy) rather than
  via a SwiftUI `App` scene, which keeps the menu-bar-agent behavior predictable.

## Tests

The model layer is covered by unit tests in `AudioPriorityTests`
(`PriorityEngineTests`, `PriorityStoreTests`). Run them from Xcode (⌘U) or:

```sh
xcodebuild test -project AudioPriority.xcodeproj -scheme AudioPriority \
  -destination 'platform=macOS'
```
