import SwiftUI

struct ErrorView: View {
    @Environment(AppState.self) private var appState
    let message: String
    let config: GenerationConfig

    private var failureTitle: String {
        if message.localizedCaseInsensitiveContains("template") {
            return "Generation too generic"
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "Generation timed out"
        }
        if message.localizedCaseInsensitiveContains("compile") || message.localizedCaseInsensitiveContains("error:") {
            return "Build failed"
        }
        return "Generation failed"
    }

    private var failureSubtitle: String {
        switch failureTitle {
        case "Generation too generic":
            return "Foundry blocked installation because the output still looked like a starter template."
        case "Generation timed out":
            return "The code generator did not finish within the allowed time."
        case "Build failed":
            return "Foundry could not compile the plugin after 3 attempts."
        default:
            return "Foundry could not finish a usable plugin from this brief."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Error icon
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.red)
                }

                // Message
                VStack(spacing: 8) {
                    Text(failureTitle)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(failureSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Details
                VStack(alignment: .leading, spacing: 6) {
                    Text("Details")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    ScrollView {
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                }
                .frame(maxWidth: 480)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle(failureTitle)
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
