import AppKit
import SwiftUI

struct ResultView: View {
    @Environment(AppState.self) private var appState
    let plugin: Plugin

    var body: some View {
        VStack(spacing: 0) {
            WindowChromeBar(title: "BUILD_COMPLETE.SH")
            topNav
            mainContent
            actionBar
        }
        .background(FoundryTheme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
    }

    // MARK: - Top Nav

    private var topNav: some View {
        HStack {
            Text("FOUNDRY")
                .font(FoundryTheme.Fonts.spaceGrotesk(20))
                .tracking(1)
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: FoundryTheme.Spacing.xs) {
                Circle()
                    .fill(FoundryTheme.Colors.trafficGreen)
                    .frame(width: 6, height: 6)
                Text("BUILD SUCCESSFUL")
                    .font(FoundryTheme.Fonts.azeretMono(11))
                    .tracking(0.9)
                    .foregroundStyle(FoundryTheme.Colors.trafficGreen)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .foundryBorder(background: FoundryTheme.Colors.backgroundSubtle, border: Color.white.opacity(0.1))

            FoundryActionButton(title: "DONE") {
                appState.popToRoot()
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
        .frame(height: FoundryTheme.Layout.headerHeight)
        .background(FoundryTheme.Colors.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                artworkSection
                    .frame(height: 240)
                infoSection
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(FoundryTheme.Colors.backgroundElevated)
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                FoundryTheme.Colors.backgroundCard
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
                    .font(FoundryTheme.Fonts.spaceGrotesk(40))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, FoundryTheme.Colors.backgroundCard],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 0) {
            ResultInfoRow(label: "PROMPT", value: plugin.prompt)
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
            ResultInfoRow(label: "TYPE", value: plugin.type.displayName.uppercased())
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
            ResultInfoRow(label: "FORMATS", value: plugin.formats.map(\.rawValue).joined(separator: " / "))
            if let au = plugin.installPaths.au {
                Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
                ResultInfoRow(label: "AU PATH", value: au)
            }
            if let vst3 = plugin.installPaths.vst3 {
                Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
                ResultInfoRow(label: "VST3 PATH", value: vst3)
            }
        }
        .background(FoundryTheme.Colors.backgroundCard)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            resultAction(label: "LIBRARY", icon: "square.grid.2x2") {
                appState.popToRoot()
            }
            Rectangle().fill(FoundryTheme.Colors.border).frame(width: 1)
            resultAction(label: "FINDER", icon: "folder") {
                openPluginFolder()
            }
            Rectangle().fill(FoundryTheme.Colors.border).frame(width: 1)
            resultAction(label: "REFINE", icon: "slider.horizontal.below.rectangle", disabled: plugin.buildDirectory == nil) {
                appState.push(.refine(plugin: plugin))
            }
        }
        .frame(height: 64)
        .background(FoundryTheme.Colors.backgroundToolbar)
        .overlay(alignment: .top) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    private func resultAction(label: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(disabled ? FoundryTheme.Colors.textFaint : FoundryTheme.Colors.textSecondary)
                Text(label)
                    .font(FoundryTheme.Fonts.azeretMono(8))
                    .tracking(1.2)
                    .foregroundStyle(disabled ? FoundryTheme.Colors.textFaint : FoundryTheme.Colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
            Text(label)
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
