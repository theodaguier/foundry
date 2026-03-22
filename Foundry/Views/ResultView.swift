import AppKit
import SwiftUI

struct ResultView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artworkSection
                    .frame(height: 240)
                infoSection
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(plugin.name)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openPluginFolder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.push(.refine(plugin: plugin))
                } label: {
                    Label("Refine", systemImage: "slider.horizontal.below.rectangle")
                }
                .disabled(plugin.buildDirectory == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    appState.popToRoot()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                Color(.controlBackgroundColor)
                if let img = loadLogoImage() {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    AbstractArtwork(pluginType: plugin.type)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.type.displayName.uppercased() + " · " + plugin.formats.map(\.rawValue).joined(separator: " / "))
                    .font(FoundryTheme.Fonts.azeretMono(9))
                    .tracking(1.2)
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)

                Text(plugin.name.uppercased())
                    .font(FoundryTheme.Fonts.spaceGrotesk(32))
                    .tracking(1)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, Color(.windowBackgroundColor)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipped()
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 0) {
            ResultInfoRow(label: "Prompt", value: plugin.prompt)
            Divider()
            ResultInfoRow(label: "Type", value: plugin.type.displayName)
            Divider()
            ResultInfoRow(label: "Formats", value: plugin.formats.map(\.rawValue).joined(separator: " / "))
            if let au = plugin.installPaths.au {
                Divider()
                ResultInfoRow(label: "AU Path", value: au)
            }
            if let vst3 = plugin.installPaths.vst3 {
                Divider()
                ResultInfoRow(label: "VST3 Path", value: vst3)
            }
        }
    }

    // MARK: - Helpers

    private func loadLogoImage() -> NSImage? {
        guard let path = plugin.logoAssetPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
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

// MARK: - Info Row

private struct ResultInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: FoundryTheme.Spacing.lg) {
            Text(label.uppercased())
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(1.2)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(FoundryTheme.Fonts.azeretMono(11))
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        ResultView(plugin: Plugin.samplePlugins[0])
    }
    .environment({
        let s = AppState()
        s.plugins = Plugin.samplePlugins
        return s
    }())
    .preferredColorScheme(.dark)
}
