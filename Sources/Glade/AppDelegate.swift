import AppKit
import GladeCore

/// Makes Glade behave like an app: double-clicking it (or opening it from the Dock/Finder while it runs)
/// shows the window. When the Claude Code hook starts it in the background it stays out of the way.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open -g` (the hook) starts us inactive; a double-click starts us active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if NSRunningApplication.current.isActive { AppWindowController.shared.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowController.shared.show()
        return true
    }
}
