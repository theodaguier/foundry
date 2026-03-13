import Foundation

struct Plugin: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: PluginType
    var prompt: String
    var createdAt: Date
    var formats: [PluginFormat]
    var installPaths: InstallPaths
    var iconColor: String
    var status: PluginStatus
    var buildDirectory: String?

    struct InstallPaths: Codable, Hashable {
        var au: String?
        var vst3: String?
    }
}

enum PluginType: String, Codable, Hashable {
    case synth
    case effect
}

enum PluginFormat: String, Codable, Hashable {
    case au = "AU"
    case vst3 = "VST3"
}

enum PluginStatus: String, Codable, Hashable {
    case installed
    case failed
    case building
}
