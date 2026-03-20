import SwiftUI
import CoreText

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct FoundryApp: App {
    @State private var appState = AppState()
    @AppStorage("appearance") private var appearance: String = AppAppearance.system.rawValue

    init() {
        FontLoader.registerAll()
    }

    private var colorScheme: ColorScheme? {
        AppAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .preferredColorScheme(colorScheme)
        }
    }
}
