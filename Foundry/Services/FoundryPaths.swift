import Foundation

enum FoundryPaths {

    static var applicationSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseDirectory.appendingPathComponent("Foundry", isDirectory: true)
    }

    static var pluginsFile: URL {
        applicationSupportDirectory.appendingPathComponent("plugins.json")
    }

    static var juceDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("JUCE", isDirectory: true)
    }

    static var pluginLogosDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("PluginLogos", isDirectory: true)
    }

    static var imageModelsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("ImageModels", isDirectory: true)
    }

    static func pluginLogoDirectory(for pluginID: UUID) -> URL {
        pluginLogosDirectory.appendingPathComponent(pluginID.uuidString, isDirectory: true)
    }

    static func pluginLogoFile(for pluginID: UUID) -> URL {
        pluginLogoDirectory(for: pluginID).appendingPathComponent("logo.png")
    }

    static var generationLogsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("GenerationLogs", isDirectory: true)
    }

    static func generationLogFile(for pluginID: UUID) -> URL {
        generationLogsDirectory.appendingPathComponent("\(pluginID.uuidString).log")
    }

    // MARK: - Telemetry

    static var telemetryDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("telemetry", isDirectory: true)
    }

    // MARK: - Versioned builds

    static var buildsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Builds", isDirectory: true)
    }

    static func pluginBuildsDirectory(for pluginID: UUID) -> URL {
        buildsDirectory.appendingPathComponent(pluginID.uuidString, isDirectory: true)
    }

    static func versionBuildDirectory(for pluginID: UUID, version: Int) -> URL {
        pluginBuildsDirectory(for: pluginID).appendingPathComponent("v\(version)", isDirectory: true)
    }
}
