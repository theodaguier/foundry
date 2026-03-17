import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var model = DependencyListModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("Checking required dependencies.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Dependency list
            GlassEffectContainer(spacing: 1) {
                VStack(spacing: 1) {
                    ForEach(Array(model.dependencies.enumerated()), id: \.element.id) { index, dep in
                        HStack(spacing: 10) {
                            DependencyStatusIcon(state: dep.state)
                                .frame(width: 16)

                            Text(dep.name)
                                .font(.body)

                            Spacer()

                            switch dep.state {
                            case .installing(let progress):
                                if progress < 0 {
                                    Text("Extracting...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(Int(progress * 100))%")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            case .missing:
                                if dep.dependency == .juce {
                                    Button("Install") {
                                        model.installJUCE(index: index)
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                } else {
                                    Text(dep.detail)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            default:
                                Text(dep.detail)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 6))
                    }
                }
            }

            if model.hasMissing {
                Label("Install missing dependencies and relaunch Foundry.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if model.allReady {
                HStack {
                    Spacer()
                    Button("Get started") {
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 360)
        .onAppear {
            model.runChecks()
        }
    }
}

#Preview {
    SetupView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
