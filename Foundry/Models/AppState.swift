import SwiftUI

// MARK: - Filters

enum PluginFilter: String, CaseIterable {
    case all = "ALL"
    case instruments = "INSTRUMENTS"
    case effects = "EFFECTS"
    case utilities = "UTILITIES"
}

enum PluginSort: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case name = "Name"
}

// MARK: - Navigation

enum Route: Hashable {
    case prompt
    case quickOptions(prompt: String)
    case generation(config: GenerationConfig)
    case refinement(config: RefineConfig)
    case refine(plugin: Plugin)
    case result(plugin: Plugin)
    case error(message: String, config: GenerationConfig)
    case queue
}

// MARK: - Generation config

struct GenerationConfig: Hashable {
    var prompt: String
    var format: FormatOption = .both
    var channelLayout: ChannelLayout = .stereo
    var presetCount: PresetCount = .five
}

struct RefineConfig: Hashable {
    var plugin: Plugin
    var modification: String
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

// MARK: - Active Build

/// Tracks an in-progress generation or refinement so the user can navigate away and return.
@Observable
@MainActor
final class ActiveBuild {
    enum Kind {
        case generation(GenerationConfig)
        case refinement(RefineConfig)
    }

    let kind: Kind
    let pipeline = GenerationPipeline()
    var elapsedSeconds: Int = 0
    var completedSteps: Set<Int> = []
    var highWaterStep: Int = 0
    var showConsole: Bool = false
    /// Set to true while the generation/refine progress view is visible.
    var isViewingProgress: Bool = false
    private var timerTask: Task<Void, Never>?

    var displayName: String {
        switch kind {
        case .generation(let config):
            String(config.prompt.prefix(40))
        case .refinement(let config):
            config.plugin.name
        }
    }

    var route: Route {
        switch kind {
        case .generation(let config): .generation(config: config)
        case .refinement(let config): .refinement(config: config)
        }
    }

    var progress: Double {
        let step = max(pipeline.currentStep.rawValue, highWaterStep)
        switch kind {
        case .generation:
            return Double(step) / Double(GenerationStep.allCases.count)
        case .refinement:
            let refineSteps: [GenerationStep] = [.generatingDSP, .generatingUI, .compiling, .installing]
            let idx = refineSteps.firstIndex(of: pipeline.currentStep) ?? 0
            return Double(idx) / Double(refineSteps.count)
        }
    }

    init(kind: Kind) {
        self.kind = kind
    }

    func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.elapsedSeconds += 1
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    func updateStep(from oldValue: GenerationStep, to newValue: GenerationStep) {
        if newValue.rawValue > highWaterStep {
            highWaterStep = newValue.rawValue
            completedSteps.insert(oldValue.rawValue)
        }
    }
}

// MARK: - App state

@Observable
@MainActor
final class AppState {
    var path = NavigationPath()
    var plugins: [Plugin] = []
    var showSetup: Bool = false
    var buildProgress: Double = 0
    var activeBuild: ActiveBuild?

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path = NavigationPath()
    }

    /// Called when a build finishes (success or error). Cleans up active build and resets navigation.
    func finishBuild() {
        activeBuild?.stopTimer()
        activeBuild = nil
        buildProgress = 0
        popToRoot()
    }

    func loadPlugins() {
        plugins = PluginManager.loadPlugins()
    }

    func refreshSetupState() async {
        let requiredDependencies: [DependencyChecker.Dependency] = [
            .xcodeTools,
            .cmake,
            .juce,
            .claudeCode,
        ]

        for dependency in requiredDependencies {
            let isInstalled = await DependencyChecker.check(dependency)
            if !isInstalled {
                showSetup = true
                return
            }
        }

        showSetup = false
    }
}

// MARK: - Sample data

extension Plugin {
    static let samplePlugins: [Plugin] = [
        Plugin(
            id: UUID(),
            name: "DrakeVox Synth",
            type: .instrument,
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
            name: "Phase Scope",
            type: .utility,
            prompt: "A stereo utility with width control, polarity flip, and a vectorscope-style meter",
            createdAt: Date(),
            formats: [.vst3],
            installPaths: InstallPaths(vst3: "~/Library/Audio/Plug-Ins/VST3/PhaseScope.vst3"),
            iconColor: "#8FB6FF",
            status: .installed
        ),
    ]
}
