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
            return "The generated plugin was missing key implementations.\nTry again with a more detailed prompt."
        case "Generation Timed Out":
            return "The code generator did not finish\nwithin the allowed time."
        case "Build Failed":
            return "Foundry could not compile the plugin\nafter multiple attempts."
        default:
            return "Foundry could not finish a usable plugin\nfrom this brief."
        }
    }

    @State private var iconAppeared = false
    @State private var textAppeared = false
    @State private var actionsAppeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "xmark.circle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)
                .scaleEffect(iconAppeared ? 1 : 0.92)
                .opacity(iconAppeared ? 1 : 0)

            VStack(spacing: 6) {
                Text(failureTitle)
                    .font(.title2)
                    .fontWeight(.medium)

                Text(failureSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: textAppeared ? 0 : 4)
            .opacity(textAppeared ? 1 : 0)

            HStack(spacing: 10) {
                Button("Back to Library") {
                    appState.popToRoot()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Retry") {
                    appState.push(.generation(config: config))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 8)
            .offset(y: actionsAppeared ? 0 : 6)
            .opacity(actionsAppeared ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Error")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                    iconAppeared = true
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.15)) {
                    textAppeared = true
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.3)) {
                    actionsAppeared = true
                }
            }
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
