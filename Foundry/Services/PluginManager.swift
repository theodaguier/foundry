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

    // MARK: - Install

    static func installPlugin(
        buildDir: URL,
        name: String,
        formats: [PluginFormat]
    ) throws -> Plugin.InstallPaths {
        let auSource = findBundle(in: buildDir, extension: "component")
        let vst3Source = findBundle(in: buildDir, extension: "vst3")

        var paths = Plugin.InstallPaths()

        // Install to /Library (system-level, visible in Finder, scanned by all DAWs)
        let auDir = "/Library/Audio/Plug-Ins/Components"
        let vst3Dir = "/Library/Audio/Plug-Ins/VST3"

        // Ad-hoc code sign the bundles so macOS/DAWs accept them
        if let src = auSource {
            codesign(src)
        }
        if let src = vst3Source {
            codesign(src)
        }

        // Build shell commands for privileged copy
        var commands: [String] = []

        if formats.contains(.au), let src = auSource {
            let dest = "\(auDir)/\(src.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("cp -R '\(src.path)' '\(dest)'")
            paths.au = dest
        }

        if formats.contains(.vst3), let src = vst3Source {
            let dest = "\(vst3Dir)/\(src.lastPathComponent)"
            commands.append("rm -rf '\(dest)'")
            commands.append("cp -R '\(src.path)' '\(dest)'")
            paths.vst3 = dest
        }

        guard !commands.isEmpty else {
            throw NSError(domain: "Foundry", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No plugin bundles found in build output"
            ])
        }

        // Run with admin privileges via osascript
        // Use single quotes in the shell script to avoid AppleScript string escaping issues
        let script = commands.joined(separator: " && ")
        // Escape backslashes and double quotes for AppleScript string literal
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

    /// Ad-hoc codesign a plugin bundle so macOS and DAWs load it
    private static func codesign(_ bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", bundleURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
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
