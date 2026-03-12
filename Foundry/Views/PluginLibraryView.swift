import SwiftUI

struct PluginLibraryView: View {
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 12)
    ]

    var body: some View {
        Group {
            if appState.plugins.isEmpty {
                emptyState
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(appState.plugins) { plugin in
                                PluginCard(plugin: plugin)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Foundry")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Plugin", systemImage: "plus") {
                    appState.push(.prompt)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No plugins yet", systemImage: "waveform")
        } description: {
            Text("Create your first audio plugin from a description.")
        } actions: {
            Button("New Plugin", systemImage: "plus") {
                appState.push(.prompt)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

#Preview {
    NavigationStack {
        PluginLibraryView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
