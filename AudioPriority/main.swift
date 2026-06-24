import AppKit

// Programmatic entry point. A SwiftUI `App` scene fights `LSUIElement`
// (it wants to create/restore windows); driving everything from the
// AppDelegate keeps the menu-bar-agent behavior predictable.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, can still show windows
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
