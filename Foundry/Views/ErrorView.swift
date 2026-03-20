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
            return "Foundry could not compile the plugin after 3 attempts."
        default:
            return "Foundry could not finish a usable plugin from this brief."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowChromeBar(title: "BUILD_FAILED.SH")
            topNav
            mainContent
            actionBar
        }
        .background(FoundryTheme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
    }

    // MARK: - Top Nav

    private var topNav: some View {
        HStack {
            Text("FOUNDRY")
                .font(FoundryTheme.Fonts.spaceGrotesk(20))
                .tracking(1)
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: FoundryTheme.Spacing.xs) {
                Circle()
                    .fill(FoundryTheme.Colors.trafficRed)
                    .frame(width: 6, height: 6)
                Text("BUILD FAILED")
                    .font(FoundryTheme.Fonts.azeretMono(11))
                    .tracking(0.9)
                    .foregroundStyle(FoundryTheme.Colors.trafficRed)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .foundryBorder(background: FoundryTheme.Colors.backgroundSubtle, border: Color.white.opacity(0.1))
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
        .frame(height: FoundryTheme.Layout.headerHeight)
        .background(FoundryTheme.Colors.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                errorHeader
                    .padding(.bottom, FoundryTheme.Spacing.xxl)

                errorDetails
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FoundryTheme.Spacing.xl)
            .padding(.vertical, FoundryTheme.Spacing.xxl)
        }
        .background(FoundryTheme.Colors.backgroundElevated)
    }

    private var errorHeader: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.md) {
            Text(failureTitle)
                .font(FoundryTheme.Fonts.spaceGrotesk(48))
                .tracking(1)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text(failureSubtitle)
                .font(FoundryTheme.Fonts.azeretMono(13))
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorDetails: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xs) {
            Text("ERROR LOG")
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(2.7)
                .foregroundStyle(FoundryTheme.Colors.textMuted)

            ScrollView {
                Text(message)
                    .font(FoundryTheme.Fonts.azeretMono(11))
                    .foregroundStyle(FoundryTheme.Colors.trafficRed.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(FoundryTheme.Spacing.lg)
            }
            .frame(maxHeight: 200)
            .background(FoundryTheme.Colors.backgroundDeep)
            .foundryBorder()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            errorAction(label: "LIBRARY", icon: "square.grid.2x2") {
                appState.popToRoot()
            }
            Rectangle().fill(FoundryTheme.Colors.border).frame(width: 1)
            errorAction(label: "EDIT PROMPT", icon: "pencil") {
                appState.popToRoot()
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    appState.push(.prompt)
                }
            }
            Rectangle().fill(FoundryTheme.Colors.border).frame(width: 1)
            errorAction(label: "RETRY", icon: "arrow.counterclockwise") {
                appState.push(.generation(config: config))
            }
        }
        .frame(height: 64)
        .background(FoundryTheme.Colors.backgroundToolbar)
        .overlay(alignment: .top) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    private func errorAction(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                Text(label)
                    .font(FoundryTheme.Fonts.azeretMono(8))
                    .tracking(1.2)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ErrorView(
            message: "Code generation failed: Generation finished but the plugin implementation is incomplete:\n– no parameters defined in createParameterLayout()\n– editor has fewer than 2 visible controls — the UI is essentially empty",
            config: GenerationConfig(prompt: "A warm analog synth")
        )
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
