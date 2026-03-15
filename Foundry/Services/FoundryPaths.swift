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
}
