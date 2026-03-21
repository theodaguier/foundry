import SwiftUI

@Observable @MainActor
final class DependencyListModel {
    var dependencies: [DependencyStatus] = [
        DependencyStatus(name: "Xcode CLI Tools", detail: "Compiler toolchain", dependency: .xcodeTools),
        DependencyStatus(name: "CMake", detail: "Build system", dependency: .cmake),
        DependencyStatus(name: "JUCE SDK", detail: "Audio framework (~200 MB)", dependency: .juce),
        DependencyStatus(name: "Claude Code CLI", detail: "npm i -g @anthropic-ai/claude-code", dependency: .claudeCode),
        DependencyStatus(name: "Codex CLI", detail: "npm i -g @openai/codex", dependency: .codex, isOptional: true),
    ]

    var allReady = false

    func runChecks() {
        for (index, dep) in dependencies.enumerated() {
            dependencies[index].state = .checking
            Task {
                let ok = await DependencyChecker.check(dep.dependency)
                dependencies[index].state = ok ? .installed : .missing
                checkAllDone()
            }
        }
    }

    func installJUCE(index: Int) {
        dependencies[index].state = .installing(0)
        Task {
            do {
                try await DependencyChecker.installJUCE { progress in
                    Task { @MainActor in
                        self.dependencies[index].state = .installing(progress)
                    }
                }
                dependencies[index].state = .installed
                checkAllDone()
            } catch {
                dependencies[index].state = .missing
            }
        }
    }

    var hasMissing: Bool {
        // Only flag required dependencies as missing
        dependencies.contains {
            if $0.isOptional { return false }
            if case .missing = $0.state { return true }
            return false
        }
    }

    private func checkAllDone() {
        // All required deps must be installed; optional deps are ignored
        let requiredReady = dependencies
            .filter { !$0.isOptional }
            .allSatisfy { if case .installed = $0.state { return true }; return false }

        // At least one agent (Claude Code or Codex) must be installed
        let agents = dependencies.filter { $0.dependency == .claudeCode || $0.dependency == .codex }
        let hasAgent = agents.contains { if case .installed = $0.state { return true }; return false }

        if requiredReady && hasAgent {
            allReady = true
        }
    }
}

struct DependencyStatus: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    var state: CheckState = .checking
    let dependency: DependencyChecker.Dependency
    var isOptional: Bool = false

    enum CheckState {
        case checking
        case installed
        case missing
        case installing(Double)
    }
}

struct DependencyStatusIcon: View {
    let state: DependencyStatus.CheckState
    var style: IconStyle = .compact

    enum IconStyle {
        case compact
        case filled
    }

    var body: some View {
        switch state {
        case .checking, .installing:
            ProgressView()
                .controlSize(.mini)
        case .installed:
            switch style {
            case .compact:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            case .filled:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
            }
        case .missing:
            switch style {
            case .compact:
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            case .filled:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
        }
    }
}
