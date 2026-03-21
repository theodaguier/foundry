import SwiftUI

struct VersionHistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let pluginID: UUID
    private let fallbackPlugin: Plugin
    var onRestore: ((PluginVersion) -> Void)?

    @State private var restoreError: String?
    @State private var versionToDelete: PluginVersion?
    @State private var isRestoring = false

    init(plugin: Plugin, onRestore: ((PluginVersion) -> Void)? = nil) {
        self.pluginID = plugin.id
        self.fallbackPlugin = plugin
        self.onRestore = onRestore
    }

    private var plugin: Plugin {
        appState.plugins.first(where: { $0.id == pluginID }) ?? fallbackPlugin
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            versionList
        }
        .frame(width: 440, height: 400)
        .background(FoundryTheme.Colors.background)
        .alert("Restore failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .alert("Clear build cache?", isPresented: Binding(
            get: { versionToDelete != nil },
            set: { if !$0 { versionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { versionToDelete = nil }
            Button("Clear", role: .destructive) {
                if let v = versionToDelete {
                    clearCache(for: v)
                    versionToDelete = nil
                }
            }
        } message: {
            if let v = versionToDelete {
                Text("This will delete the build files for v\(v.versionNumber). You won't be able to restore this version afterward.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VERSION HISTORY")
                    .font(FoundryTheme.Fonts.azeretMono(11))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Text(plugin.name)
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - List

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(plugin.versions.sorted(by: { $0.versionNumber > $1.versionNumber })) { version in
                    VStack(spacing: 0) {
                        versionRow(version)
                        Rectangle().fill(FoundryTheme.Colors.border).frame(height: 1)
                    }
                }
            }
        }
    }

    private func versionRow(_ version: PluginVersion) -> some View {
        HStack(spacing: 12) {
            // Version badge
            VStack(spacing: 2) {
                Text("v\(version.versionNumber)")
                    .font(FoundryTheme.Fonts.spaceGrotesk(16))
                    .foregroundStyle(version.isActive ? .primary : FoundryTheme.Colors.textSecondary)
                if version.isActive {
                    Text("ACTIVE")
                        .font(FoundryTheme.Fonts.azeretMono(7))
                        .tracking(1)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(FoundryTheme.Colors.border)
                }
            }
            .frame(width: 56)

            // Details
            VStack(alignment: .leading, spacing: 3) {
                Text(version.prompt)
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(FoundryTheme.Fonts.azeretMono(9))
                        .foregroundStyle(FoundryTheme.Colors.textFaint)

                    if version.hasBuildCache {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 8))
                            .foregroundStyle(FoundryTheme.Colors.textFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            if version.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
                    .font(.system(size: 14))
            } else {
                Menu {
                    Button("Restore", systemImage: "arrow.counterclockwise") {
                        restoreVersion(version)
                    }
                    .disabled(!version.hasBuildCache)
                    if version.hasBuildCache {
                        Button("Clear build cache", systemImage: "trash", role: .destructive) {
                            versionToDelete = version
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(version.isActive ? FoundryTheme.Colors.backgroundCard : .clear)
    }

    // MARK: - Actions

    private func restoreVersion(_ version: PluginVersion) {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            do {
                let installPaths = try PluginManager.installVersion(version, for: plugin)

                var updated = plugin
                updated.installPaths = installPaths
                updated.status = .installed
                updated.currentVersion = version.versionNumber
                updated.buildDirectory = version.buildDirectory

                // Update active flags
                updated.versions = updated.versions.map { v in
                    var copy = v
                    copy.isActive = (v.id == version.id)
                    return copy
                }

                PluginManager.update(updated, in: &appState.plugins)
                isRestoring = false
            } catch {
                isRestoring = false
                restoreError = error.localizedDescription
            }
        }
    }

    private func clearCache(for version: PluginVersion) {
        PluginManager.clearBuildCache(for: version)

        // Update the version in the plugin to reflect cleared cache
        var updated = plugin
        updated.versions = updated.versions.map { v in
            guard v.id == version.id else { return v }
            return PluginVersion(
                id: v.id,
                pluginId: v.pluginId,
                versionNumber: v.versionNumber,
                prompt: v.prompt,
                createdAt: v.createdAt,
                buildDirectory: nil,
                installPaths: v.installPaths,
                iconColor: v.iconColor,
                isActive: v.isActive,
                agent: v.agent,
                model: v.model
            )
        }
        PluginManager.update(updated, in: &appState.plugins)
    }
}

// MARK: - Preview

#Preview {
    VersionHistoryView(plugin: Plugin.samplePlugins[0])
        .environment({
            let state = AppState()
            state.plugins = Plugin.samplePlugins
            return state
        }())
        .preferredColorScheme(.dark)
}
