import Foundation

enum PluginManager {

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Foundry/plugins.json")
    }

    // MARK: - Read

    static func loadPlugins() -> [Plugin] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            let wrapper = try JSONDecoder.foundry.decode(PluginFile.self, from: data)
            return wrapper.plugins
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
        plugins.removeAll { $0.id == id }
        save(plugins)
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
        let auSource = findBundle(in: buildDir, extension: "component")
        let vst3Source = findBundle(in: buildDir, extension: "vst3")

        var paths = Plugin.InstallPaths()

        // Install to /Library (system-level, visible by all DAWs)
        let auDir = "/Library/Audio/Plug-Ins/Components"
        let vst3Dir = "/Library/Audio/Plug-Ins/VST3"

        // Build shell commands for privileged copy, xattr clear, and codesign
        var commands: [String] = []

        if formats.contains(.au), let src = auSource {
            let dest = "\(auDir)/\(src.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("ditto '\(src.path)' '\(dest)'")
            commands.append("xattr -cr '\(dest)'")
            commands.append("codesign --force --deep --sign - '\(dest)'")
            paths.au = dest
        }

        if formats.contains(.vst3), let src = vst3Source {
            let dest = "\(vst3Dir)/\(src.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("ditto '\(src.path)' '\(dest)'")
            commands.append("xattr -cr '\(dest)'")
            commands.append("codesign --force --deep --sign - '\(dest)'")
            paths.vst3 = dest
        }

        guard !commands.isEmpty else {
            throw NSError(domain: "Foundry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No plugin bundles found in build output"
            ])
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

        return paths
    }

    // MARK: - Helpers

    /// Set the bundle bit so Finder shows the directory as a single file (like other AU/VST3 plugins)
    private static func markAsBundle(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isPackage = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private static func findBundle(in dir: URL, extension ext: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension == ext {
                return url
            }
        }
        return nil
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
