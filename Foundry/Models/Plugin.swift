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

enum PluginType: Codable, Hashable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .instrument: "instrument"
        case .effect: "effect"
        case .utility: "utility"
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
