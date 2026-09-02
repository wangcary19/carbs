// carbs — menu-bar dropdown: display-only readout + Settings… (⌘,) + Quit

import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: CarbsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today: \(Int((model.todayDevice + model.todayModel).rounded())) g CO₂e")
                .font(.headline)
            Text("Device \(Int(model.todayDevice.rounded()))g · Models \(Int(model.todayModel.rounded()))g")
            Text(model.zoneLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.watchersLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("7 days: \(Int(model.week.rounded()))g · 30 days: \(Int(model.month.rounded()))g")
                .font(.caption)
            Divider()
            // showSettingsWindow: is the macOS 13-safe way to open a SwiftUI
            // Settings scene (Environment.openSettings requires macOS 14).
            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit carbs") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
    }
}
