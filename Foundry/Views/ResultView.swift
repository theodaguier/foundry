import SwiftUI

struct ResultView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Success icon
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.green)
                }

                // Plugin info
                VStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(plugin.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)

                    Text("Installed and ready to use")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Format badges
                HStack(spacing: 8) {
                    ForEach(plugin.formats, id: \.self) { format in
                        Label(format.rawValue, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                    }
                }

                // Prompt recap
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(plugin.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                }
                .frame(maxWidth: 420)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle(plugin.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Show in Finder", systemImage: "folder") {
                    openPluginFolder()
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .automatic) {
                Button("Refine", systemImage: "slider.horizontal.below.rectangle") {
                    appState.push(.refine(plugin: plugin))
                }
                .buttonStyle(.glass)
                .disabled(plugin.buildDirectory == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    appState.popToRoot()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func openPluginFolder() {
        if let vst3 = plugin.installPaths.vst3 {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: vst3)])
        } else if let au = plugin.installPaths.au {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: au)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Library/Audio/Plug-Ins/"))
        }
    }
}

#Preview {
    NavigationStack {
        ResultView(plugin: Plugin.samplePlugins[0])
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
