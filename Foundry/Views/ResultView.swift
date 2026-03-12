import SwiftUI

struct ResultView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("Installed and ready to use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(plugin.formats, id: \.self) { format in
                    Label(format.rawValue, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                Text(plugin.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(20)
        .navigationTitle(plugin.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Show in Finder", systemImage: "folder") {
                    openPluginFolder()
                }
                .buttonStyle(.glass)
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
        // Open the system-level plugin directory where DAWs look
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
