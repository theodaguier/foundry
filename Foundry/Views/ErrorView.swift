import SwiftUI

struct ErrorView: View {
    @Environment(AppState.self) private var appState
    let message: String
    let config: GenerationConfig

    private var failureTitle: String {
        if message.localizedCaseInsensitiveContains("incomplete") || message.localizedCaseInsensitiveContains("insufficient") {
            return "Implementation Incomplete"
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "Generation Timed Out"
        }
        if message.localizedCaseInsensitiveContains("compile") || message.localizedCaseInsensitiveContains("error:") {
            return "Build Failed"
        }
        return "Generation Failed"
    }

    private var failureSubtitle: String {
        switch failureTitle {
        case "Implementation Incomplete":
            return "The generated plugin was missing key implementations (parameters, DSP, or UI controls)."
        case "Generation Timed Out":
            return "The code generator did not finish within the allowed time."
        case "Build Failed":
            return "Foundry could not compile the plugin after multiple attempts."
        default:
            return "Foundry could not finish a usable plugin from this brief."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failureTitle)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(failureSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error Log")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        ScrollView {
                            Text(message)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                        }
                        .frame(maxHeight: 200)
                        .background(Color(.controlBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            HStack(spacing: 12) {
                Button {
                    appState.popToRoot()
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }

                Button {
                    appState.popToRoot()
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        appState.push(.prompt)
                    }
                } label: {
                    Label("Edit Prompt", systemImage: "pencil")
                }

                Button("Retry") {
                    appState.push(.generation(config: config))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .navigationTitle("Build Failed")
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        ErrorView(
            message: "Code generation failed: Generation finished but the plugin implementation is incomplete:\n– no parameters defined in createParameterLayout()\n– editor has fewer than 2 visible controls",
            config: GenerationConfig(prompt: "A warm analog synth")
        )
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
