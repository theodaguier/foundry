import SwiftUI

struct DependencyStatus: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    var state: CheckState
    let dependency: DependencyChecker.Dependency

    enum CheckState {
        case checking
        case installed
        case missing
        case installing(Double) // progress 0–1, or -1 for indeterminate
    }
}

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var dependencies: [DependencyStatus] = [
        DependencyStatus(name: "Xcode CLI Tools", detail: "Compiler toolchain", state: .checking, dependency: .xcodeTools),
        DependencyStatus(name: "CMake", detail: "Build system", state: .checking, dependency: .cmake),
        DependencyStatus(name: "JUCE SDK", detail: "Audio framework (~200 MB)", state: .checking, dependency: .juce),
        DependencyStatus(name: "Claude Code CLI", detail: "npm i -g @anthropic-ai/claude-code", state: .checking, dependency: .claudeCode),
    ]

    @State private var allReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Checking required dependencies.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GlassEffectContainer(spacing: 1) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(dependencies.enumerated()), id: \.element.id) { index, dep in
                        HStack(spacing: 10) {
                            statusIcon(dep.state)
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
                                        installJUCE(index: index)
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

            if dependencies.contains(where: { if case .missing = $0.state { return true }; return false }) {
                Text("Install missing dependencies and relaunch Foundry.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if allReady {
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
        .frame(width: 460, height: 340)
        .onAppear {
            runChecks()
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: DependencyStatus.CheckState) -> some View {
        switch state {
        case .checking, .installing:
            ProgressView()
                .controlSize(.mini)
        case .installed:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)
        case .missing:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private func runChecks() {
        for (index, dep) in dependencies.enumerated() {
            Task {
                try? await Task.sleep(for: .milliseconds(index * 200 + 100))
                let ok = await DependencyChecker.check(dep.dependency)
                withAnimation(.easeOut(duration: 0.15)) {
                    dependencies[index].state = ok ? .installed : .missing
                }
                checkAllDone()
            }
        }
    }

    private func installJUCE(index: Int) {
        dependencies[index].state = .installing(0)
        Task {
            do {
                try await DependencyChecker.installJUCE { progress in
                    Task { @MainActor in
                        dependencies[index].state = .installing(progress)
                    }
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    dependencies[index].state = .installed
                }
                checkAllDone()
            } catch {
                withAnimation(.easeOut(duration: 0.15)) {
                    dependencies[index].state = .missing
                }
            }
        }
    }

    private func checkAllDone() {
        let allInstalled = dependencies.allSatisfy {
            if case .installed = $0.state { return true }
            return false
        }
        if allInstalled {
            withAnimation(.easeOut(duration: 0.15).delay(0.2)) {
                allReady = true
            }
        }
    }
}

#Preview {
    SetupView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
