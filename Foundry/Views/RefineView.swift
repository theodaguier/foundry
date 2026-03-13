import SwiftUI

struct RefineView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    @State private var modification = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                // Plugin context
                VStack(alignment: .leading, spacing: 6) {
                    Text("Refining \(plugin.name)")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text(plugin.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Modification input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What do you want to change?")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $modification)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(height: 100)
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 10))
                }
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Refine")
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Apply") {
                    let config = RefineConfig(
                        plugin: plugin,
                        modification: modification
                    )
                    appState.push(.refinement(config: config))
                }
                .buttonStyle(.glassProminent)
                .disabled(modification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    NavigationStack {
        RefineView(plugin: Plugin.samplePlugins[0])
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
