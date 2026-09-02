import SwiftUI

/// ⌘, settings window. Actions and preferences live here so the menu-bar
/// dropdown stays display-only.
/// Note: deliberately avoids @State/@FocusState — the icon field binds live to
/// the model, so no local editing state is needed.
struct SettingsView: View {
    @ObservedObject var model: CarbsModel

    var body: some View {
        Form {
            HStack {
                TextField("Menu bar icon:", text: Binding(
                    get: { model.menuBarIcon },
                    set: { model.setMenuBarIcon($0) }
                ))
                Button("Reset") { model.setMenuBarIcon(AppConfig.defaultMenuBarIcon) }
            }
            Text("Shown before the grams, e.g. “CO₂ 142g”. Leave empty for grams only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            TextField("Electricity Maps token:", text: Binding(
                get: { model.gridTokenDraft },
                set: { model.gridTokenDraft = $0 }
            ))
            .onSubmit { model.applyGridToken() }
            HStack {
                Button("Save Token") { model.applyGridToken() }
                if model.gridTokenSaved {
                    Text("✓ live grid data enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Optional — free personal tier (one zone, hourly) for live data. Without it, carbs estimates from bundled averages. Stored in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Divider()
            HStack {
                Button("Open Config Folder") { model.openConfig() }
                Button("Export CSV…") { model.exportCSV() }
            }
            Button("Reset Totals") { model.resetTotals() }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 340)
    }
}
