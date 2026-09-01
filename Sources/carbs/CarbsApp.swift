import SwiftUI

@main
struct CarbsApp: App {
    @StateObject private var model = CarbsModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
                .onAppear { model.start() }
        } label: {
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
