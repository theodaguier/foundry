import SwiftUI

struct ErrorView: View {
    @Environment(AppState.self) private var appState
    let message: String
    let config: GenerationConfig

    private var failureTitle: String {
        if message.localizedCaseInsensitiveContains("incomplete") || message.localizedCaseInsensitiveContains("insufficient") {
            return "IMPLEMENTATION INCOMPLETE"
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "GENERATION TIMED OUT"
        }
        if message.localizedCaseInsensitiveContains("compile") || message.localizedCaseInsensitiveContains("error:") {
            return "BUILD FAILED"
        }
        return "GENERATION FAILED"
    }

    private var failureSubtitle: String {
        switch failureTitle {
        case "IMPLEMENTATION INCOMPLETE":
            return "The generated plugin was missing key implementations (parameters, DSP, or UI controls)."
        case "GENERATION TIMED OUT":
            return "The code generator did not finish within the allowed time."
        case "BUILD FAILED":
            return "Foundry could not compile the plugin after multiple attempts."
        default:
            return "Foundry could not finish a usable plugin from this brief."
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 80)
            content
                .frame(maxWidth: 640)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Error")
        .navigationBarBackButtonHidden(true)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "xmark.circle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .padding(.bottom, FoundryTheme.Spacing.lg)

            // Title
            Text(failureTitle)
                .font(FoundryTheme.Fonts.azeretMono(13, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(FoundryTheme.Colors.textPrimary)
                .padding(.bottom, FoundryTheme.Spacing.xs)

            // Subtitle
            Text(failureSubtitle)
                .font(FoundryTheme.Fonts.azeretMono(12))
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, FoundryTheme.Spacing.xl)

            // Error log
            VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xs) {
                Text("ERROR LOG")
                    .font(FoundryTheme.Fonts.azeretMono(10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                ScrollView {
                    Text(message)
                        .font(FoundryTheme.Fonts.azeretMono(11))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(FoundryTheme.Spacing.md)
                }
                .frame(maxHeight: 160)
                .background(Color(.textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(FoundryTheme.Colors.border.opacity(0.6), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, FoundryTheme.Spacing.xl)

            // Actions
            HStack(spacing: FoundryTheme.Spacing.sm) {
                Button("Library") {
                    appState.popToRoot()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Edit Prompt") {
                    appState.popToRoot()
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        appState.push(.prompt)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Retry") {
                    appState.push(.generation(config: config))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        ErrorView(
            message: "Code generation failed: Claude did not create the required source files",
            config: GenerationConfig(prompt: "A warm analog synth")
        )
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
