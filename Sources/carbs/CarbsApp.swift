import SwiftUI

@main
struct CarbsApp: App {
    @StateObject private var model: CarbsModel

    init() {
        let m = CarbsModel()
        _model = StateObject(wrappedValue: m)
        // MenuBarExtra renders its content lazily on first click, so timers must
        // start here at launch — not in MenuView.onAppear — or nothing samples
        // until the user opens the menu.
        Task { @MainActor in m.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }

        // Single on-demand window (macOS 13+): never opens at launch,
        // only via openWindow(id: "stats") from the dropdown.
        Window("carbs — usage stats", id: "stats") {
            StatsView(model: model)
        }
    }
}
