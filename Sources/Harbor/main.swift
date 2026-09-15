import AppKit

// The entry point is AppKit, not SwiftUI's `WindowGroup`: the window and the menu
// bar item are both created deliberately, and neither may be duplicated.
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
