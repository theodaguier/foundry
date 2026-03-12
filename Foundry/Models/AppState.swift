import SwiftUI

// MARK: - Navigation

enum Route: Hashable {
    case prompt
    case quickOptions(prompt: String)
    case generation(config: GenerationConfig)
    case result(plugin: Plugin)
    case error(message: String, config: GenerationConfig)
}

// MARK: - Generation config

struct GenerationConfig: Hashable {
    var prompt: String
    var format: FormatOption = .both
    var channelLayout: ChannelLayout = .stereo
    var presetCount: PresetCount = .five
}

enum FormatOption: String, CaseIterable, Hashable {
    case au = "AU"
    case vst3 = "VST3"
    case both = "Both"
}

enum ChannelLayout: String, CaseIterable, Hashable {
    case mono = "Mono"
    case stereo = "Stereo"
}

enum PresetCount: Int, CaseIterable, Hashable {
    case zero = 0
    case three = 3
    case five = 5
    case ten = 10

    var label: String {
        switch self {
        case .zero: "None"
        case .three: "3"
        case .five: "5"
        case .ten: "10"
        }
    }
}

// MARK: - App state

@Observable
final class AppState {
    var path = NavigationPath()
    var plugins: [Plugin] = []
    var showSetup: Bool = false

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func loadPlugins() {
        plugins = PluginManager.loadPlugins()
    }
}

// MARK: - Sample data

extension Plugin {
    static let samplePlugins: [Plugin] = [
        Plugin(
            id: UUID(),
            name: "DrakeVox Synth",
            type: .synth,
            prompt: "An RnB synth with Drake-style presets",
            createdAt: Date().addingTimeInterval(-86400),
            formats: [.au, .vst3],
            installPaths: InstallPaths(
                au: "~/Library/Audio/Plug-Ins/Components/DrakeVoxSynth.component",
                vst3: "~/Library/Audio/Plug-Ins/VST3/DrakeVoxSynth.vst3"
            ),
            iconColor: "#E8E5E0",
            status: .installed
        ),
        Plugin(
            id: UUID(),
            name: "Tape Saturation",
            type: .effect,
            prompt: "Warm analog tape saturation effect",
            createdAt: Date().addingTimeInterval(-172800),
            formats: [.au, .vst3],
            installPaths: InstallPaths(
                au: "~/Library/Audio/Plug-Ins/Components/TapeSaturation.component",
                vst3: "~/Library/Audio/Plug-Ins/VST3/TapeSaturation.vst3"
            ),
            iconColor: "#FFB347",
            status: .installed
        ),
        Plugin(
            id: UUID(),
            name: "Crystal Reverb",
            type: .effect,
            prompt: "Shimmering reverb with pitch shifting",
            createdAt: Date(),
            formats: [.vst3],
            installPaths: InstallPaths(vst3: "~/Library/Audio/Plug-Ins/VST3/CrystalReverb.vst3"),
            iconColor: "#4A9EFF",
            status: .installed
        ),
    ]
}
