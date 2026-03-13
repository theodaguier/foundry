import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = AppAppearance.system.rawValue

    @State private var dependencies: [DependencyStatus] = [
        DependencyStatus(name: "Xcode CLI Tools", detail: "Compiler toolchain", state: .checking, dependency: .xcodeTools),
        DependencyStatus(name: "CMake", detail: "Build system", state: .checking, dependency: .cmake),
        DependencyStatus(name: "JUCE SDK", detail: "Audio framework (~200 MB)", state: .checking, dependency: .juce),
        DependencyStatus(name: "Claude Code CLI", detail: "npm i -g @anthropic-ai/claude-code", state: .checking, dependency: .claudeCode),
    ]

    private let pluginPaths = [
        ("AU Components", "~/Library/Audio/Plug-Ins/Components/"),
        ("VST3 Plugins", "~/Library/Audio/Plug-Ins/VST3/"),
        ("Plugin Data", "~/Library/Application Support/Foundry/"),
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            dependenciesTab
                .tabItem {
                    Label("Dependencies", systemImage: "shippingbox")
                }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Plugin Paths") {
                ForEach(pluginPaths, id: \.0) { label, path in
                    LabeledContent(label) {
                        HStack(spacing: 6) {
                            Text(path)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Button {
                                let expanded = NSString(string: path).expandingTildeInPath
                                NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Dependencies

    private var dependenciesTab: some View {
        Form {
            Section {
                ForEach(Array(dependencies.enumerated()), id: \.element.id) { index, dep in
                    HStack {
                        statusIcon(dep.state)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(dep.name)
                                .font(.body)
                            Text(dep.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        switch dep.state {
                        case .installing(let progress):
                            if progress < 0 {
                                Text("Extracting...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView(value: progress)
                                    .frame(width: 60)
                            }
                        case .missing:
                            if dep.dependency == .juce {
                                Button("Install") {
                                    installJUCE(index: index)
                                }
                                .controlSize(.small)
                            } else {
                                Text("Missing")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        case .installed:
                            Text("Installed")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .checking:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Required")
            } footer: {
                if dependencies.contains(where: { if case .missing = $0.state { return true }; return false }) {
                    Text("Install missing dependencies to use Foundry.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Recheck All") {
                    runChecks()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            runChecks()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(_ state: DependencyStatus.CheckState) -> some View {
        switch state {
        case .checking, .installing:
            ProgressView()
                .controlSize(.mini)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .missing:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        }
    }

    private func runChecks() {
        for (index, dep) in dependencies.enumerated() {
            dependencies[index].state = .checking
            Task {
                try? await Task.sleep(for: .milliseconds(index * 150 + 100))
                let ok = await DependencyChecker.check(dep.dependency)
                withAnimation(.easeOut(duration: 0.15)) {
                    dependencies[index].state = ok ? .installed : .missing
                }
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
            } catch {
                withAnimation(.easeOut(duration: 0.15)) {
                    dependencies[index].state = .missing
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
