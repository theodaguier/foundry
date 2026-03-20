import AppKit
import SwiftUI

// MARK: - Library View

struct PluginLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: PluginFilter = .all
    @State private var selectedPlugin: Plugin?
    @State private var pluginToDelete: Plugin?
    @State private var pluginToRename: Plugin?
    @State private var renameText = ""
    @State private var deleteError: String?

    private var filteredPlugins: [Plugin] {
        var result = appState.plugins
        switch filter {
        case .all: break
        case .instruments: result = result.filter { $0.type == .instrument }
        case .effects: result = result.filter { $0.type == .effect }
        case .utilities: result = result.filter { $0.type == .utility }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            FoundryHeaderBar(
                activeFilter: filter,
                onFilterTap: { filter = $0 },
                onLogoTap: {}
            ) {
                HStack(spacing: FoundryTheme.Spacing.md) {
                    FoundryActionButton(title: "+ NEW") {
                        appState.push(.prompt)
                    }

                    if let building = appState.plugins.first(where: { $0.status == .building }) {
                        BuildingIndicator(name: building.name)
                    }
                }
            }

            ScrollView {
                pluginGrid
            }
            .background(FoundryTheme.Colors.backgroundElevated)

        }
        .background(FoundryTheme.Colors.backgroundElevated)
        .sheet(item: $selectedPlugin) { plugin in
            PluginDetailView(plugin: plugin) { action in
                handleDetailAction(action, for: plugin)
            }
        }
        .alert("Delete \(pluginToDelete?.name ?? "plugin")?",
               isPresented: Binding(
                   get: { pluginToDelete != nil },
                   set: { if !$0 { pluginToDelete = nil } }
               )
        ) {
            Button("Cancel", role: .cancel) { pluginToDelete = nil }
            Button("Delete", role: .destructive) {
                if let plugin = pluginToDelete { deletePlugin(plugin) }
            }
        } message: {
            Text("This will uninstall the AU/VST3 files from your system. This cannot be undone.")
        }
        .alert("Rename Plugin",
               isPresented: Binding(
                   get: { pluginToRename != nil },
                   set: { if !$0 { pluginToRename = nil } }
               )
        ) {
            TextField("Plugin name", text: $renameText)
            Button("Cancel", role: .cancel) { pluginToRename = nil }
            Button("Rename") {
                if let plugin = pluginToRename { renamePlugin(plugin, to: renameText) }
            }
        }
        .alert("Could not delete plugin",
               isPresented: Binding(
                   get: { deleteError != nil },
                   set: { if !$0 { deleteError = nil } }
               )
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Plugin Grid

    private var pluginGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 1), count: 5)
        return LazyVGrid(columns: cols, spacing: 1) {
            NewPluginCard { appState.push(.prompt) }
            ForEach(filteredPlugins) { plugin in
                LibraryPluginCard(plugin: plugin) {
                    selectedPlugin = plugin
                } onRename: {
                    pluginToRename = plugin
                    renameText = plugin.name
                } onShowInFinder: {
                    showInFinder(plugin)
                } onDelete: {
                    pluginToDelete = plugin
                }
            }
        }
        .background(FoundryTheme.Colors.backgroundSubtle)
    }

    // MARK: - Actions

    private func deletePlugin(_ plugin: Plugin) {
        do {
            try PluginManager.uninstallPlugin(plugin)
            PluginManager.remove(id: plugin.id, from: &appState.plugins)
        } catch {
            deleteError = error.localizedDescription
        }
        pluginToDelete = nil
    }

    private func renamePlugin(_ plugin: Plugin, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else {
            pluginToRename = nil
            return
        }
        var updated = plugin
        updated.name = newName.trimmingCharacters(in: .whitespaces)
        PluginManager.update(updated, in: &appState.plugins)
        pluginToRename = nil
    }

    private func showInFinder(_ plugin: Plugin) {
        if let vst3 = plugin.installPaths.vst3 {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: vst3)])
        } else if let au = plugin.installPaths.au {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: au)])
        }
    }

    private func handleDetailAction(_ action: PluginDetailAction, for plugin: Plugin) {
        selectedPlugin = nil
        switch action {
        case .delete:
            pluginToDelete = plugin
        case .rename:
            pluginToRename = plugin
            renameText = plugin.name
        case .regenerate:
            appState.push(.quickOptions(prompt: plugin.prompt))
        case .showInFinder:
            showInFinder(plugin)
        }
    }
}

// MARK: - Building Indicator

struct BuildingIndicator: View {
    let name: String
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: FoundryTheme.Spacing.xs) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            Text("BUILDING · \(Int(appState.buildProgress * 100))%")
                .font(FoundryTheme.Fonts.jetBrainsMono(9))
                .tracking(0.9)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - New Plugin Card

struct NewPluginCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: FoundryTheme.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .thin))
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                Text("NEW PLUGIN")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .tracking(2)
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 340)
            .background(FoundryTheme.Colors.backgroundCard)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        FoundryTheme.Colors.borderSubtle,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .padding(1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library Plugin Card

struct LibraryPluginCard: View {
    let plugin: Plugin
    let onTap: () -> Void
    var onRename: (() -> Void)?
    var onShowInFinder: (() -> Void)?
    var onDelete: (() -> Void)?
    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                artworkArea
                    .frame(height: 204)
                infoArea
            }
            .frame(maxWidth: .infinity)
            .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...", systemImage: "pencil") { onRename?() }
            Button("Show in Finder", systemImage: "folder") { onShowInFinder?() }
            Divider()
            Button("Delete Plugin", systemImage: "trash", role: .destructive) { onDelete?() }
        }
    }

    @ViewBuilder
    private var artworkArea: some View {
        ZStack {
            FoundryTheme.Colors.backgroundCard
            if plugin.status == .building {
                buildingArtwork
            } else if let img = loadLogoImage() {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                AbstractArtwork(pluginType: plugin.type)
            }
        }
    }

    private var buildingArtwork: some View {
        Rectangle()
            .strokeBorder(
                FoundryTheme.Colors.borderSubtle,
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .padding(32)
            .overlay(
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .ultraLight))
                    .foregroundStyle(FoundryTheme.Colors.borderSubtle)
            )
    }

    private var infoArea: some View {
        ZStack(alignment: .bottomLeading) {
            (plugin.status == .building ? Color(hex: 0x1F1F1F) : FoundryTheme.Colors.backgroundToolbar)
            VStack(alignment: .leading, spacing: 3) {
                if plugin.status == .building {
                    Text(plugin.name.uppercased())
                        .font(FoundryTheme.Fonts.spaceGrotesk(20))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    Text("BUILDING... \(Int(appState.buildProgress * 100))%")
                        .font(FoundryTheme.Fonts.jetBrainsMono(9))
                        .tracking(1.8)
                        .foregroundStyle(.white)
                } else {
                    Text(plugin.name.uppercased())
                        .font(FoundryTheme.Fonts.spaceGrotesk(24))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(formatSubtitle())
                    .font(FoundryTheme.Fonts.jetBrainsMono(9))
                    .tracking(0.9)
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 13)

            if plugin.status == .building {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color(hex: 0x353535).frame(height: 4)
                            Color.white.frame(width: geo.size.width * appState.buildProgress, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(height: 136)
    }

    private func formatSubtitle() -> String {
        let type = plugin.type.displayName.uppercased()
        let formats = plugin.formats.map(\.rawValue).joined(separator: " / ")
        return "\(type) · \(formats)"
    }

    private func loadLogoImage() -> NSImage? {
        guard let path = plugin.logoAssetPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment({
            let state = AppState()
            state.plugins = Plugin.samplePlugins
            return state
        }())
        .preferredColorScheme(.dark)
}
