import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.authState {
            case .checking:
                launchScreen
            case .unauthenticated:
                AuthContainerView()
            case .authenticated:
                authenticatedContent
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task {
            await appState.checkExistingSession()
            await appState.observeAuthChanges()
        }
    }

    // MARK: - Launch Screen

    private var launchScreen: some View {
        VStack(spacing: FoundryTheme.Spacing.md) {
            Image("FoundryLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Authenticated Content

    private var authenticatedContent: some View {
        @Bindable var state = appState

        return NavigationStack(path: $state.path) {
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
                case .queue:
                    BuildQueueView()
                case .account:
                    AccountView()
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
