import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = AppAppearance.system.rawValue

    @State private var model = DependencyListModel()

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
                ForEach(Array(model.dependencies.enumerated()), id: \.element.id) { index, dep in
                    HStack {
                        DependencyStatusIcon(state: dep.state, style: .filled)
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
                                    model.installJUCE(index: index)
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
                if model.hasMissing {
                    Text("Install missing dependencies to use Foundry.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Recheck All") {
                    model.runChecks()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.runChecks()
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
