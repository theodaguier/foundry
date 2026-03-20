import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationStack(path: $state.path) {
            Group {
                if appState.plugins.isEmpty && !state.showSetup {
                    WelcomeView()
                } else {
                    PluginLibraryView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .prompt:
                        PromptView()

                    case .quickOptions(let prompt):
                        QuickOptionsView(prompt: prompt)

                    case .generation(let config):
                        GenerationProgressView(config: config)

                    case .refinement(let config):
                        RefineProgressView(config: config)

                    case .refine(let plugin):
                        RefineView(plugin: plugin)

                    case .result(let plugin):
                        ResultView(plugin: plugin)

                    case .error(let message, let config):
                        ErrorView(message: message, config: config)
                    }
                }
        }
        .sheet(isPresented: $state.showSetup) {
            SetupView()
        }
        .onAppear {
            appState.loadPlugins()
            BuildDirectoryCleaner.sweepStaleDirectories()
        }
        .task {
            await appState.refreshSetupState()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
