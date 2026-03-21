import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Welcome to Foundry")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Generate real, compilable audio plugins\nfrom a natural language description.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Build Your First Plugin") {
                appState.push(.prompt)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Foundry")
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
