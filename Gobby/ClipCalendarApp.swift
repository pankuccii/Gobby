import SwiftUI

@main
struct ClipCalendarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Gobby", systemImage: "clipboard.fill") {
            ContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
