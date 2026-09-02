// carbs — programmatic windows (openWindow/showSettingsWindow: are unreliable from MenuBarExtra)

import AppKit
import SwiftUI

/// NSWindow-based presenters. From a menu-bar-only app, both Environment.openWindow
/// and the Settings scene's showSettingsWindow: action are unreliable on recent
/// macOS versions — hosting SwiftUI views in our own NSWindows always works.
@MainActor
enum WindowManager {
    private static var windows: [String: NSWindow] = [:]

    static func show(id: String, title: String, size: NSSize, content: some View) {
        let w: NSWindow
        if let existing = windows[id] {
            w = existing
        } else {
            w = NSWindow(contentViewController: NSHostingController(rootView: content))
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(size)
            w.isReleasedWhenClosed = false
            w.center()
            windows[id] = w
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func showStats(model: CarbsModel) {
        show(id: "stats", title: "carbs — usage stats",
             size: NSSize(width: 460, height: 300),
             content: StatsView(model: model))
    }

    static func showSettings(model: CarbsModel) {
        show(id: "settings", title: "carbs — settings",
             size: NSSize(width: 400, height: 340),
             content: SettingsView(model: model))
    }
}
