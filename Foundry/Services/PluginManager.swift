import Foundation

enum PluginManager {

    private static var storageURL: URL {
        FoundryPaths.pluginsFile
    }

    // MARK: - Read

    static func loadPlugins() -> [Plugin] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            let wrapper = try JSONDecoder.foundry.decode(PluginFile.self, from: data)
            let plugins = wrapper.plugins.map(refreshStatus(for:))
            if plugins != wrapper.plugins {
                save(plugins)
            }
            return plugins
        } catch {
            print("[PluginManager] Failed to load plugins: \(error)")
            return []
        }
    }

    // MARK: - Write

    static func save(_ plugins: [Plugin]) {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder.foundry.encode(PluginFile(plugins: plugins))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[PluginManager] Failed to save plugins: \(error)")
        }
    }

    static func add(_ plugin: Plugin, to plugins: inout [Plugin]) {
        plugins.insert(plugin, at: 0)
        save(plugins)
    }

    static func remove(id: UUID, from plugins: inout [Plugin]) {
        if let plugin = plugins.first(where: { $0.id == id }) {
            removeLogoAssets(for: plugin)
            clearAllBuildCaches(for: plugin.id)
        }
        plugins.removeAll { $0.id == id }
        save(plugins)
    }

    static func update(_ plugin: Plugin, in plugins: inout [Plugin]) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[index] = plugin
        save(plugins)
    }

    private static func refreshStatus(for plugin: Plugin) -> Plugin {
        var updated = plugin

        let auValid = plugin.installPaths.au.map {
            PluginBundleInspector.bundleLooksUsable(at: URL(fileURLWithPath: $0), format: .au)
        }
        let vst3Valid = plugin.installPaths.vst3.map {
            PluginBundleInspector.bundleLooksUsable(at: URL(fileURLWithPath: $0), format: .vst3)
        }

        let requiredChecks = plugin.formats.compactMap { format -> Bool? in
            switch format {
            case .au:
                return auValid
            case .vst3:
                return vst3Valid
            }
        }

        if !requiredChecks.isEmpty {
            updated.status = requiredChecks.allSatisfy { $0 } ? .installed : .failed
        }

        return updated
    }

    // MARK: - Uninstall

    static func uninstallPlugin(_ plugin: Plugin) throws {
        var commands: [String] = []
        if let au = plugin.installPaths.au {
            commands.append("rm -rf '\(au)'")
        }
        if let vst3 = plugin.installPaths.vst3 {
            commands.append("rm -rf '\(vst3)'")
        }
        guard !commands.isEmpty else { return }

        let script = commands.joined(separator: " && ")
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"

        var error: NSDictionary?
        let scriptObj = NSAppleScript(source: appleScript)
        scriptObj?.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(domain: "Foundry", code: 3, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    // MARK: - Install

    static func installPlugin(
        buildDir: URL,
        name: String,
        formats: [PluginFormat]
    ) throws -> Plugin.InstallPaths {
        let auSource = PluginBundleInspector.locateBestBundle(in: buildDir, format: .au)
        let vst3Source = PluginBundleInspector.locateBestBundle(in: buildDir, format: .vst3)

        var paths = Plugin.InstallPaths()

        // Install to /Library (system-level, visible by all DAWs)
        let auDir = "/Library/Audio/Plug-Ins/Components"
        let vst3Dir = "/Library/Audio/Plug-Ins/VST3"

        // Build shell commands for privileged copy, xattr clear, and codesign
        var commands: [String] = []

        if formats.contains(.au), let src = auSource {
            let dest = "\(auDir)/\(src.bundleURL.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("ditto '\(src.bundleURL.path)' '\(dest)'")
            commands.append("xattr -cr '\(dest)'")
            commands.append("codesign --force --deep --sign - '\(dest)'")
            paths.au = dest
        }

        if formats.contains(.vst3), let src = vst3Source {
            let dest = "\(vst3Dir)/\(src.bundleURL.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("ditto '\(src.bundleURL.path)' '\(dest)'")
            commands.append("xattr -cr '\(dest)'")
            commands.append("codesign --force --deep --sign - '\(dest)'")
            paths.vst3 = dest
        }

        guard !commands.isEmpty else {
            throw NSError(domain: "Foundry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No plugin bundles found in build output"
            ])
        }

        if formats.contains(.au), auSource == nil {
            throw PluginBundleInspector.ValidationError.bundleNotFound(.au)
        }

        if formats.contains(.vst3), vst3Source == nil {
            throw PluginBundleInspector.ValidationError.bundleNotFound(.vst3)
        }

        if formats.contains(.au) {
            commands.append("killall AudioComponentRegistrar >/dev/null 2>&1 || true")
        }

        let script = commands.joined(separator: " && ")
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedScript)\" with administrator privileges"

        var error: NSDictionary?
        let scriptObj = NSAppleScript(source: appleScript)
        scriptObj?.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(domain: "Foundry", code: 2, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        // Give AudioComponentRegistrar time to restart and re-scan after being killed
        if formats.contains(.au) {
            Thread.sleep(forTimeInterval: 3.0)
        }

        if let auPath = paths.au {
            try PluginBundleInspector.validateInstalledBundle(
                at: URL(fileURLWithPath: auPath),
                format: .au
            )
        }

        if let vst3Path = paths.vst3 {
            try PluginBundleInspector.validateInstalledBundle(
                at: URL(fileURLWithPath: vst3Path),
                format: .vst3
            )
        }

        return paths
    }

    // MARK: - Version management

    /// Archive a build directory to the persistent versioned storage.
    /// Returns the path of the archived directory.
    static func archiveBuild(from sourceDir: URL, pluginID: UUID, version: Int) throws -> String {
        let dest = FoundryPaths.versionBuildDirectory(for: pluginID, version: version)
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceDir, to: dest)
        return dest.path
    }

    /// Install a specific version's bundles to the system plug-in directories.
    static func installVersion(_ version: PluginVersion, for plugin: Plugin) throws -> Plugin.InstallPaths {
        guard let buildDir = version.buildDirectory,
              FileManager.default.fileExists(atPath: buildDir) else {
            throw NSError(domain: "Foundry", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Build directory for v\(version.versionNumber) not found — cache may have been cleared"
            ])
        }
        return try installPlugin(
            buildDir: URL(fileURLWithPath: buildDir),
            name: plugin.name,
            formats: plugin.formats
        )
    }

    /// Delete the archived build directory for a version to free disk space.
    static func clearBuildCache(for version: PluginVersion) {
        guard let dir = version.buildDirectory else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: dir))
    }

    /// Remove all versioned build caches for a plugin.
    static func clearAllBuildCaches(for pluginID: UUID) {
        let dir = FoundryPaths.pluginBuildsDirectory(for: pluginID)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Helpers

    private static func removeLogoAssets(for plugin: Plugin) {
        let logoDirectory = FoundryPaths.pluginLogoDirectory(for: plugin.id)
        try? FileManager.default.removeItem(at: logoDirectory)
    }

}

// MARK: - Storage format

private struct PluginFile: Codable {
    var plugins: [Plugin]
}

// MARK: - Coder config

extension JSONEncoder {
    static var foundry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var foundry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
