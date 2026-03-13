import SwiftUI

struct ResultView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
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
                VStack(spacing: 10) {
                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(plugin.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: .capsule)

                    Text("Installed and ready to use in your DAW")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Format badges
                HStack(spacing: 8) {
                    ForEach(plugin.formats, id: \.self) { format in
                        Label(format.rawValue, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.1), in: .capsule)
                    }
                }

                // Prompt recap
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(plugin.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 8))
                }
                .frame(maxWidth: 420)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle(plugin.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to Library", systemImage: "chevron.left") {
                    appState.popToRoot()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Show in Finder", systemImage: "folder") {
                    openPluginFolder()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Refine", systemImage: "slider.horizontal.below.rectangle") {
                    appState.push(.refine(plugin: plugin))
                }
                .disabled(plugin.buildDirectory == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    appState.popToRoot()
                }
                .buttonStyle(.borderedProminent)
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
