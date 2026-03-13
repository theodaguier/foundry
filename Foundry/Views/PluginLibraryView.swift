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

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 12)
    ]

    private var filteredPlugins: [Plugin] {
        var result = appState.plugins

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.prompt.lowercased().contains(query)
            }
        }

        // Type filter
        switch filter {
        case .all: break
        case .instruments: result = result.filter { $0.type == .instrument }
        case .effects: result = result.filter { $0.type == .effect }
        case .utilities: result = result.filter { $0.type == .utility }
        }

        // Sort
        switch sort {
        case .newest: result.sort { $0.createdAt > $1.createdAt }
        case .oldest: result.sort { $0.createdAt < $1.createdAt }
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return result
    }

    var body: some View {
        Group {
            if appState.plugins.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Toolbar: search + filters
                    filterBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if filteredPlugins.isEmpty {
                        noResultsState
                    } else {
                        ScrollView {
                            // Count
                            HStack {
                                Text("\(filteredPlugins.count) plugin\(filteredPlugins.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filteredPlugins) { plugin in
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
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .navigationTitle("Foundry")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Plugin", systemImage: "plus") {
                    appState.push(.prompt)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(item: $selectedPlugin) { plugin in
            PluginDetailView(plugin: plugin) { action in
                handleDetailAction(action, for: plugin)
            }
        }
        // Delete confirmation
        .alert("Delete \(pluginToDelete?.name ?? "plugin")?",
               isPresented: Binding(
                   get: { pluginToDelete != nil },
                   set: { if !$0 { pluginToDelete = nil } }
               )
        ) {
            Button("Cancel", role: .cancel) {
                pluginToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let plugin = pluginToDelete {
                    deletePlugin(plugin)
                }
            }
        } message: {
            Text("This will uninstall the AU/VST3 files from your system. This cannot be undone.")
        }
        // Rename
        .alert("Rename Plugin",
               isPresented: Binding(
                   get: { pluginToRename != nil },
                   set: { if !$0 { pluginToRename = nil } }
               )
        ) {
            TextField("Plugin name", text: $renameText)
            Button("Cancel", role: .cancel) {
                pluginToRename = nil
            }
            Button("Rename") {
                if let plugin = pluginToRename {
                    renamePlugin(plugin, to: renameText)
                }
            }
        }
        // Error
        .alert("Could not delete plugin", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: 240)

            // Type filter
            Picker("Type", selection: $filter) {
                ForEach(PluginFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            // Sort
            Menu {
                ForEach(PluginSort.allCases, id: \.self) { s in
                    Button {
                        sort = s
                    } label: {
                        HStack {
                            Text(s.rawValue)
                            if sort == s {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No plugins yet")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("Create your first audio plugin from a description.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("New Plugin", systemImage: "plus") {
                appState.push(.prompt)
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.tertiary)

            Text("No matching plugins")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Clear Filters") {
                searchText = ""
                filter = .all
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
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
