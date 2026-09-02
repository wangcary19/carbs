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
            HStack(spacing: 8) {
                Button { WindowManager.showStats(model: model) } label: {
                    Label("Stats", systemImage: "chart.bar")
                        .frame(maxWidth: .infinity)
                }
                Button { WindowManager.showSettings(model: model) } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(",")
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
