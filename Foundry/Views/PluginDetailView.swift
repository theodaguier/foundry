import AppKit
import SwiftUI

enum PluginDetailAction {
    case delete
    case rename
    case regenerate
    case refine
    case showInFinder
    case restoreVersion(PluginVersion)
}

struct PluginDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let pluginID: UUID
    private let fallbackPlugin: Plugin
    var onAction: ((PluginDetailAction) -> Void)?

    @State private var logoProgress: PluginLogoProgress?
    @State private var logoTask: Task<Void, Never>?
    @State private var logoError: String?
    @State private var showingVersionHistory = false

    init(plugin: Plugin, onAction: ((PluginDetailAction) -> Void)? = nil) {
        self.pluginID = plugin.id
        self.fallbackPlugin = plugin
        self.onAction = onAction
    }

    private var plugin: Plugin {
        appState.plugins.first(where: { $0.id == pluginID }) ?? fallbackPlugin
    }

    var body: some View {
        VStack(spacing: 0) {
            artworkSection

            infoSection

            if !plugin.versions.isEmpty {
                versionSection
            }

            actionSection
        }
        .frame(width: 520)
        .background(FoundryTheme.Colors.background)
        .sheet(isPresented: $showingVersionHistory) {
            VersionHistoryView(plugin: plugin) { version in
                onAction?(.restoreVersion(version))
            }
            .environment(appState)
        }
        .overlay {
            if let logoProgress {
                LogoProgressOverlay(progress: logoProgress) {
                    logoTask?.cancel()
                }
            }
        }
        .alert("Logo generation failed", isPresented: Binding(
            get: { logoError != nil },
            set: { if !$0 { logoError = nil } }
        )) {
            Button("OK") { logoError = nil }
        } message: {
            Text(logoError ?? "")
        }
        .onDisappear { logoTask?.cancel() }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Background artwork
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
            .frame(height: 200)

            // Name + type overlay
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
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 60)
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
            InfoRow(label: "PROMPT", value: plugin.prompt)
            Separator()
            InfoRow(label: "CREATED", value: plugin.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let au = plugin.installPaths.au {
                Separator()
                InfoRow(label: "AU PATH", value: au)
            }
            if let vst3 = plugin.installPaths.vst3 {
                Separator()
                InfoRow(label: "VST3 PATH", value: vst3)
            }
        }
        .background(FoundryTheme.Colors.backgroundCard)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    // MARK: - Version

    private var versionSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VERSION")
                    .font(FoundryTheme.Fonts.azeretMono(9))
                    .tracking(1.2)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)

                Spacer()

                Button {
                    showingVersionHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Text("v\(plugin.currentVersion)")
                            .font(FoundryTheme.Fonts.azeretMono(11))
                            .foregroundStyle(FoundryTheme.Colors.textSecondary)
                        Text("·")
                            .foregroundStyle(FoundryTheme.Colors.textFaint)
                        Text("\(plugin.versions.count) version\(plugin.versions.count == 1 ? "" : "s")")
                            .font(FoundryTheme.Fonts.azeretMono(11))
                            .foregroundStyle(FoundryTheme.Colors.textMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FoundryTheme.Colors.textFaint)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(FoundryTheme.Colors.backgroundCard)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        HStack {
            Menu {
                Button("Show in Finder", systemImage: "folder") {
                    onAction?(.showInFinder)
                }
                Button("Rename", systemImage: "pencil") {
                    onAction?(.rename)
                }
                Button("Refine", systemImage: "slider.horizontal.below.rectangle") {
                    onAction?(.refine)
                }
                Button("Regenerate", systemImage: "arrow.counterclockwise") {
                    onAction?(.regenerate)
                }
                Button("Generate Logo", systemImage: "photo.badge.sparkles") {
                    startLogoGeneration()
                }
                .disabled(logoTask != nil)
                if plugin.generationLogPath != nil {
                    Button("View Logs", systemImage: "doc.text") {
                        if let path = plugin.generationLogPath {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onAction?(.delete)
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func loadLogoImage() -> NSImage? {
        guard let path = plugin.logoAssetPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func startLogoGeneration() {
        guard logoTask == nil else { return }
        let currentPlugin = plugin
        logoProgress = .preparing("Preparing logo generation…")
        logoTask = Task {
            do {
                let updatedPlugin = try await PluginLogoService.generateLogo(for: currentPlugin) { progress in
                    Task { @MainActor in logoProgress = progress }
                }
                try Task.checkCancellation()
                await MainActor.run {
                    PluginManager.update(updatedPlugin, in: &appState.plugins)
                    logoProgress = nil
                    logoTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { logoProgress = nil; logoTask = nil }
            } catch {
                await MainActor.run { logoProgress = nil; logoTask = nil; logoError = error.localizedDescription }
            }
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
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
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Detail Action

private struct DetailAction: View {
    let label: String
    let icon: String
    var destructive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(destructive ? Color.red : (disabled ? FoundryTheme.Colors.textFaint : FoundryTheme.Colors.textSecondary))
                Text(label)
                    .font(FoundryTheme.Fonts.azeretMono(8))
                    .tracking(1.2)
                    .foregroundStyle(destructive ? Color.red : (disabled ? FoundryTheme.Colors.textFaint : FoundryTheme.Colors.textMuted))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Separators

private struct Separator: View {
    var body: some View {
        Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
    }
}

private struct VerticalSeparator: View {
    var body: some View {
        Rectangle().fill(FoundryTheme.Colors.border).frame(width: 1)
    }
}

// MARK: - Logo Progress Overlay

struct LogoProgressOverlay: View {
    let progress: PluginLogoProgress
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.85).ignoresSafeArea()

            VStack(spacing: FoundryTheme.Spacing.md) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.primary)

                Text(progress.message.uppercased())
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(1.5)
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(FoundryTheme.Fonts.azeretMono(10))
                        .tracking(2)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(FoundryTheme.Spacing.xxl)
            .background(FoundryTheme.Colors.backgroundElevated)
            .overlay(
                Rectangle()
                    .stroke(FoundryTheme.Colors.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    PluginDetailView(plugin: Plugin.samplePlugins[0])
        .environment({
            let state = AppState()
            state.plugins = Plugin.samplePlugins
            return state
        }())
        .preferredColorScheme(.dark)
}
