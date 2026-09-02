// carbs — menu-bar dropdown: display-only readout + Settings… (⌘,) + Quit

import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: CarbsModel
    @Environment(\.openWindow) private var openWindow

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
            HStack(spacing: 18) {
                Button { openWindow(id: "stats") } label: {
                    Image(systemName: "chart.bar")
                }
                .help("Usage stats")

                // showSettingsWindow: is the macOS 13-safe way to open a SwiftUI
                // Settings scene (Environment.openSettings requires macOS 14).
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .keyboardShortcut(",")
                .help("Settings (⌘,)")

                Spacer()

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "xmark")
                }
                .help("Quit carbs")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14))
        }
        .padding(12)
        .frame(width: 280)
    }
}
