import SwiftUI

struct ErrorView: View {
    @Environment(AppState.self) private var appState
    let message: String
    let config: GenerationConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text("Could not compile the plugin after 3 attempts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox {
                ScrollView {
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            } label: {
                Text("Compiler output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 520)

            Spacer()
        }
        .padding(20)
        .navigationTitle("Build failed")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Edit prompt") {
                    appState.popToRoot()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.push(.prompt)
                    }
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Retry") {
                    appState.push(.generation(config: config))
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ErrorView(
            message: "error: use of undeclared identifier 'oscillator'\n  PluginProcessor.cpp:42:5",
            config: GenerationConfig(prompt: "A warm analog synth")
        )
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
