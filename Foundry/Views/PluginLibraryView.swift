import SwiftUI

// MARK: - Filter

enum PluginFilter: String, CaseIterable {
    case all = "All"
    case instruments = "Instruments"
    case effects = "Effects"
    case utilities = "Utilities"
}

enum PluginSort: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case name = "Name"
}

struct PluginLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var filter: PluginFilter = .all
    @State private var sort: PluginSort = .newest
    @State private var selectedPlugin: Plugin?
    @State private var pluginToDelete: Plugin?
    @State private var pluginToRename: Plugin?
    @State private var renameText = ""
    @State private var deleteError: String?

    private var filteredPlugins: [Plugin] {
        var result = appState.plugins

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.prompt.lowercased().contains(query)
            }
        }

        switch filter {
        case .all: break
        case .instruments: result = result.filter { $0.type == .instrument }
        case .effects: result = result.filter { $0.type == .effect }
        case .utilities: result = result.filter { $0.type == .utility }
        }

        switch sort {
        case .newest: result.sort { $0.createdAt > $1.createdAt }
        case .oldest: result.sort { $0.createdAt < $1.createdAt }
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return result
    }

    /// Split into 3 columns, filling left-to-right per row
    private var columns: [[Plugin]] {
        var col0: [Plugin] = []
        var col1: [Plugin] = []
        var col2: [Plugin] = []
        for (i, plugin) in filteredPlugins.enumerated() {
            switch i % 3 {
            case 0: col0.append(plugin)
            case 1: col1.append(plugin)
            default: col2.append(plugin)
            }
        }
        return [col0, col1, col2]
    }

    var body: some View {
        Group {
            if appState.plugins.isEmpty {
                emptyState
            } else if filteredPlugins.isEmpty {
                noResultsState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Recently created — large cards
                        if searchText.isEmpty && filter == .all {
                            recentSection
                        }

                        // All plugins — App Store grid
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("All Plugins")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(filteredPlugins.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            appStoreGrid
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Foundry")
        .searchable(text: $searchText, prompt: "Search plugins...")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("Filter", selection: $filter) {
                    ForEach(PluginFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    ForEach(PluginSort.allCases, id: \.self) { s in
                        Button {
                            sort = s
                        } label: {
                            if sort == s {
                                Label(s.rawValue, systemImage: "checkmark")
                            } else {
                                Text(s.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.push(.prompt)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
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
        .alert("Could not delete plugin", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Recent Section

    private var recentPlugins: [Plugin] {
        Array(
            appState.plugins
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(2)
        )
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recently Created")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                ForEach(recentPlugins) { plugin in
                    largePluginCard(plugin)
                }
            }
        }
    }

    private func largePluginCard(_ plugin: Plugin) -> some View {
        Button {
            selectedPlugin = plugin
        } label: {
            HStack(spacing: 0) {
                // Text content — left side
                VStack(alignment: .leading, spacing: 6) {
                    Text(plugin.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(plugin.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(plugin.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(20)

                Spacer(minLength: 0)

                PluginArtworkView(
                    plugin: plugin,
                    size: 80,
                    cornerRadius: 22,
                    symbolSize: 30
                )
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Color(.controlBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - App Store Grid

    private var appStoreGrid: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(0..<3, id: \.self) { colIndex in
                VStack(spacing: 0) {
                    let items = columns[colIndex]
                    ForEach(Array(items.enumerated()), id: \.element.id) { rowIndex, plugin in
                        if rowIndex > 0 {
                            Divider()
                                .padding(.leading, 46)
                        }

                        pluginCardView(for: plugin)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pluginCardView(for plugin: Plugin) -> some View {
        PluginCard(plugin: plugin) {
            selectedPlugin = plugin
        } onDelete: {
            pluginToDelete = plugin
        } onShowInFinder: {
            showInFinder(plugin)
        } onRename: {
            pluginToRename = plugin
            renameText = plugin.name
        } onRegenerate: {
            appState.push(.quickOptions(prompt: plugin.prompt))
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("No plugins yet")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Create your first audio plugin from a description.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button("New Plugin", systemImage: "plus") {
                appState.push(.prompt)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("No matching plugins")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("Clear Filters") {
                searchText = ""
                filter = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview {
    NavigationStack {
        PluginLibraryView()
    }
    .environment({
        let state = AppState()
        state.plugins = Plugin.samplePlugins
        return state
    }())
    .preferredColorScheme(.dark)
}
