import Foundation
import SwiftUI

// MARK: - Plugin Version

struct PluginVersion: Identifiable, Codable, Hashable {
    let id: UUID
    let pluginId: UUID
    let versionNumber: Int
    let prompt: String
    let createdAt: Date
    let buildDirectory: String?
    let installPaths: Plugin.InstallPaths
    let iconColor: String
    var isActive: Bool
    var agent: GenerationAgent?
    var model: AgentModel?
    var telemetryId: UUID?

    /// Whether the archived build directory still exists on disk.
    var hasBuildCache: Bool {
        guard let dir = buildDirectory else { return false }
        return FileManager.default.fileExists(atPath: dir)
    }
}

// MARK: - Plugin

struct Plugin: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: PluginType
    var prompt: String
    var createdAt: Date
    var formats: [PluginFormat]
    var installPaths: InstallPaths
    var iconColor: String
    var logoAssetPath: String?
    var status: PluginStatus
    var buildDirectory: String? = nil
    var generationLogPath: String? = nil
    var agent: GenerationAgent? = nil
    var model: AgentModel? = nil
    var currentVersion: Int = 1
    var versions: [PluginVersion] = []

    struct InstallPaths: Codable, Hashable {
        var au: String?
        var vst3: String?
    }

    // Custom decoder so existing plugins.json (without currentVersion/versions) still loads
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(PluginType.self, forKey: .type)
        prompt = try c.decode(String.self, forKey: .prompt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        formats = try c.decode([PluginFormat].self, forKey: .formats)
        installPaths = try c.decode(InstallPaths.self, forKey: .installPaths)
        iconColor = try c.decode(String.self, forKey: .iconColor)
        logoAssetPath = try c.decodeIfPresent(String.self, forKey: .logoAssetPath)
        status = try c.decode(PluginStatus.self, forKey: .status)
        buildDirectory = try c.decodeIfPresent(String.self, forKey: .buildDirectory)
        generationLogPath = try c.decodeIfPresent(String.self, forKey: .generationLogPath)
        agent = try c.decodeIfPresent(GenerationAgent.self, forKey: .agent)
        model = try c.decodeIfPresent(AgentModel.self, forKey: .model)
        currentVersion = try c.decodeIfPresent(Int.self, forKey: .currentVersion) ?? 1
        versions = try c.decodeIfPresent([PluginVersion].self, forKey: .versions) ?? []
    }

    init(
        id: UUID,
        name: String,
        type: PluginType,
        prompt: String,
        createdAt: Date,
        formats: [PluginFormat],
        installPaths: InstallPaths,
        iconColor: String,
        logoAssetPath: String? = nil,
        status: PluginStatus,
        buildDirectory: String? = nil,
        generationLogPath: String? = nil,
        agent: GenerationAgent? = nil,
        model: AgentModel? = nil,
        currentVersion: Int = 1,
        versions: [PluginVersion] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.prompt = prompt
        self.createdAt = createdAt
        self.formats = formats
        self.installPaths = installPaths
        self.iconColor = iconColor
        self.logoAssetPath = logoAssetPath
        self.status = status
        self.buildDirectory = buildDirectory
        self.generationLogPath = generationLogPath
        self.agent = agent
        self.model = model
        self.currentVersion = currentVersion
        self.versions = versions
    }

    /// The currently active version, if any.
    var activeVersion: PluginVersion? {
        versions.first(where: { $0.isActive })
    }

    /// Next version number for a new generation or refine.
    var nextVersionNumber: Int {
        (versions.map(\.versionNumber).max() ?? 0) + 1
    }
}

enum PluginType: String, Codable, Hashable {
    case instrument
    case effect
    case utility

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "instrument", "synth":
            self = .instrument
        case "effect":
            self = .effect
        case "utility":
            self = .utility
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown plugin type: \(value)"
            )
        }
    }

    var displayName: String {
        switch self {
        case .instrument: "Instrument"
        case .effect: "Effect"
        case .utility: "Utility"
        }
    }

    var systemImage: String {
        switch self {
        case .instrument: "pianokeys"
        case .effect: "waveform"
        case .utility: "dial.low"
        }
    }
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

// MARK: - Hex color

extension Plugin {
    var color: Color {
        guard iconColor.hasPrefix("#"),
              let hex = UInt(iconColor.dropFirst(), radix: 16) else {
            return .accentColor
        }
        return Color(hex: hex)
    }
}
