import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var logoAppeared = false
    @State private var textAppeared = false
    @State private var buttonAppeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("FoundryLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .foregroundStyle(.secondary)
                .scaleEffect(logoAppeared ? 1 : 0.92)
                .opacity(logoAppeared ? 1 : 0)

            VStack(spacing: 6) {
                Text("Welcome to Foundry")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Generate real, compilable audio plugins\nfrom a natural language description.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: textAppeared ? 0 : 4)
            .opacity(textAppeared ? 1 : 0)

            Button("Build Your First Plugin") {
                appState.push(.prompt)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .padding(.top, 8)
            .offset(y: buttonAppeared ? 0 : 6)
            .opacity(buttonAppeared ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Foundry")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                    logoAppeared = true
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.15)) {
                    textAppeared = true
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.3)) {
                    buttonAppeared = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
