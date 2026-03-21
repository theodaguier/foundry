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
    case account
}

// MARK: - Agent & model selection (loaded from models.json)

/// A provider (e.g. Claude Code, Codex) with its available models.
struct AgentProvider: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let command: String
    let models: [AgentModel]

    var defaultModel: AgentModel {
        models.first(where: { $0.isDefault }) ?? models[0]
    }
}

/// A model within a provider (e.g. Sonnet, o3).
struct AgentModel: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let flag: String
    var `default`: Bool?

    var isDefault: Bool { `default` ?? false }
    var displayName: String { name }
    var cliFlag: String { flag }
}

/// Loads the provider/model catalog from models.json (bundled or user-overridden).
enum ModelCatalog {
    private struct Root: Codable {
        let providers: [AgentProvider]
    }

    /// Cached catalog, loaded once.
    static let providers: [AgentProvider] = {
        // 1. Check user override in Application Support
        let userFile = FoundryPaths.applicationSupportDirectory.appendingPathComponent("models.json")
        if let data = try? Data(contentsOf: userFile),
           let root = try? JSONDecoder().decode(Root.self, from: data) {
            return root.providers
        }

        // 2. Fall back to bundled resource
        if let url = Bundle.main.url(forResource: "models", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let root = try? JSONDecoder().decode(Root.self, from: data) {
            return root.providers
        }

        // 3. Hardcoded emergency fallback
        return [
            AgentProvider(
                id: "claude-code", name: "Claude Code", icon: "ProviderAnthropic", command: "claude",
                models: [AgentModel(id: "sonnet", name: "Sonnet", subtitle: "Fast & capable", flag: "sonnet", default: true)]
            )
        ]
    }()

    /// All models across all providers.
    static var allModels: [AgentModel] {
        providers.flatMap(\.models)
    }

    /// Find the provider for a given model.
    static func provider(for model: AgentModel) -> AgentProvider {
        providers.first(where: { $0.models.contains(model) }) ?? providers[0]
    }

    /// Find a provider by its id.
    static func provider(byId id: String) -> AgentProvider? {
        providers.first(where: { $0.id == id })
    }

    /// Find a model by its id.
    static func model(byId id: String) -> AgentModel? {
        allModels.first(where: { $0.id == id })
    }

    /// The global default model (first provider's default).
    static var defaultModel: AgentModel {
        providers[0].defaultModel
    }
}

// MARK: - Legacy GenerationAgent bridging
//
// These keep existing code (DependencyChecker, pipeline, services) working
// without a massive rewrite. They map to/from the dynamic catalog.

enum GenerationAgent: String, CaseIterable, Codable, Hashable {
    case claudeCode = "Claude Code"
    case codex = "Codex"

    var displayName: String { rawValue }

    var providerId: String {
        switch self {
        case .claudeCode: "claude-code"
        case .codex: "codex"
        }
    }

    var provider: AgentProvider? {
        ModelCatalog.provider(byId: providerId)
    }

    var defaultModel: AgentModel {
        provider?.defaultModel ?? ModelCatalog.defaultModel
    }

    init?(providerId: String) {
        switch providerId {
        case "claude-code": self = .claudeCode
        case "codex": self = .codex
        default: return nil
        }
    }
}

// MARK: - Generation config

struct GenerationConfig: Hashable {
    var prompt: String
    var format: FormatOption = .both
    var channelLayout: ChannelLayout = .stereo
    var presetCount: PresetCount = .five
    var agent: GenerationAgent = .claudeCode
    var model: AgentModel = ModelCatalog.defaultModel
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

// MARK: - Auth state

enum AuthState {
    case checking
    case unauthenticated
    case authenticated
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

    // Auth
    var authState: AuthState = .checking
    var userProfile: UserProfile?

    var isAuthenticated: Bool {
        authState == .authenticated
    }

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
        // Core dependencies are always required
        let coreDependencies: [DependencyChecker.Dependency] = [
            .xcodeTools,
            .cmake,
            .juce,
        ]

        for dependency in coreDependencies {
            let isInstalled = await DependencyChecker.check(dependency)
            if !isInstalled {
                showSetup = true
                return
            }
        }

        // At least one agent must be available
        let hasClaudeCode = await DependencyChecker.check(.claudeCode)
        let hasCodex = await DependencyChecker.check(.codex)

        if !hasClaudeCode && !hasCodex {
            showSetup = true
            return
        }

        showSetup = false
    }

    // MARK: - Auth

    /// Check for existing session on app launch
    func checkExistingSession() async {
        authState = .checking
        if let session = await AuthService.shared.currentSession {
            authState = .authenticated
            await loadProfile(userId: session.user.id)
        } else {
            authState = .unauthenticated
        }
    }

    /// Listen for auth state changes (sign in, sign out, token refresh)
    func observeAuthChanges() async {
        for await (event, session) in AuthService.shared.authStateChanges {
            switch event {
            case .signedIn:
                authState = .authenticated
                if let user = session?.user {
                    await loadProfile(userId: user.id)
                }
            case .signedOut:
                authState = .unauthenticated
                userProfile = nil
                path = NavigationPath()
            default:
                break
            }
        }
    }

    /// Called after successful sign in from auth views
    func handleSignIn() async {
        authState = .authenticated
        if let userId = await AuthService.shared.currentUser?.id {
            await loadProfile(userId: userId)
        }
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
        } catch {
            // Force local sign out even if network fails
        }
        authState = .unauthenticated
        userProfile = nil
        path = NavigationPath()
    }

    private func loadProfile(userId: UUID) async {
        do {
            userProfile = try await AuthService.shared.getProfile(userId: userId)
        } catch {
            // Profile may not exist yet (first sign in with Apple)
            userProfile = nil
        }
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
