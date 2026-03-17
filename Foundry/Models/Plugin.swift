import Foundation
import SwiftUI

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
        return Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
