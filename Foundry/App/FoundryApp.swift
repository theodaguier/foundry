import SwiftUI

@main
struct FoundryApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
    }
}
