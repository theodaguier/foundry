import Foundation

// MARK: - Generation type

enum GenerationType: String, Codable {
    case generate
    case refine
    case preset
}

// MARK: - Telemetry record

struct GenerationTelemetry: Codable, Identifiable {

    // Identity
    let id: UUID
    let pluginId: UUID?
    let versionNumber: Int?

    // Type
    let generationType: GenerationType

    // Agent
    let agent: GenerationAgent
    let model: String

    // Prompt
    let originalPrompt: String
    let enhancedPrompt: String?
    let systemPromptVersion: String

    // Timing (seconds)
    let startedAt: Date
    let enhancerDuration: Double?
    let generationDuration: Double
    let auditDuration: Double?
    let buildDuration: Double
    let installDuration: Double?
    let totalDuration: Double

    // Token usage
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let totalTokens: Int?

    // Cost
    let estimatedCostUSD: Double?

    // Build
    let buildAttempts: Int
    let buildLogs: [BuildAttemptLog]

    // Outcome
    let outcome: GenerationOutcome
    let failureStage: FailureStage?
    let failureMessage: String?
    let failureDetails: String?

    // Plugin config
    let pluginType: PluginType
    let format: FormatOption
    let channelLayout: ChannelLayout
    let presetCount: Int

    // Environment
    let macOSVersion: String
    let cpuArchitecture: String
    let xcodeVersion: String?
    let juceVersion: String?
    let agentCLIVersion: String?
}

// MARK: - Build attempt log

struct BuildAttemptLog: Codable, Identifiable {
    var id: Int { attemptNumber }
    let attemptNumber: Int
    let duration: Double
    let success: Bool
    let errors: String?
    let fixPassDuration: Double?
    let fixPassTokens: Int?
}

// MARK: - Outcome

enum GenerationOutcome: String, Codable {
    case success
    case failedGeneration
    case failedQualityCheck
    case failedBuild
    case failedInstall
    case failedSmokeTest
    case cancelled
    case timedOut
}

// MARK: - Failure stage

enum FailureStage: String, Codable {
    case assembly
    case promptEnhancement
    case generation
    case qualityEnforcement
    case build
    case install
    case smokeTest
}

// MARK: - Token usage

struct TokenUsage: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheWriteTokens += other.cacheWriteTokens
    }
}

// MARK: - Mutable builder

/// Accumulated during the pipeline, then finalized into an immutable `GenerationTelemetry`.
@MainActor
final class TelemetryBuilder {
    let id = UUID()
    var pluginId: UUID?
    var versionNumber: Int?

    var generationType: GenerationType = .generate

    var agent: GenerationAgent = .claudeCode
    var model: String = ""

    var originalPrompt: String = ""
    var enhancedPrompt: String?
    var systemPromptVersion: String = "1.0"

    var startedAt = Date()
    var generationStart: Date?
    var generationEnd: Date?
    var auditStart: Date?
    var auditEnd: Date?
    var buildStart: Date?
    var buildEnd: Date?
    var installStart: Date?
    var installEnd: Date?

    var tokenUsage = TokenUsage()

    var buildLogs: [BuildAttemptLog] = []
    var currentBuildAttemptStart: Date?
    var currentFixStart: Date?
    var currentFixTokens: Int?

    var outcome: GenerationOutcome = .success
    var failureStage: FailureStage?
    var failureMessage: String?
    var failureDetails: String?

    var pluginType: PluginType = .effect
    var format: FormatOption = .both
    var channelLayout: ChannelLayout = .stereo
    var presetCount: Int = 5

    // Environment (populated once on init)
    let macOSVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    let cpuArchitecture: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }()

    var xcodeVersion: String?
    var juceVersion: String?
    var agentCLIVersion: String?

    // MARK: - Build tracking

    func startBuildAttempt() {
        currentBuildAttemptStart = Date()
    }

    func endBuildAttempt(number: Int, success: Bool, errors: String?) {
        let duration = currentBuildAttemptStart.map { -$0.timeIntervalSinceNow } ?? 0
        let fixDuration = currentFixStart.map { -$0.timeIntervalSinceNow } ?? nil

        buildLogs.append(BuildAttemptLog(
            attemptNumber: number,
            duration: duration,
            success: success,
            errors: errors,
            fixPassDuration: fixDuration,
            fixPassTokens: currentFixTokens
        ))

        currentBuildAttemptStart = nil
        currentFixStart = nil
        currentFixTokens = nil
    }

    func startFixPass() {
        currentFixStart = Date()
    }

    // MARK: - Finalize

    func build() -> GenerationTelemetry {
        let now = Date()

        let genDuration = if let s = generationStart, let e = generationEnd {
            e.timeIntervalSince(s)
        } else {
            0.0
        }
        let auditDur: Double? = if let s = auditStart, let e = auditEnd {
            e.timeIntervalSince(s)
        } else {
            nil
        }
        let bldDuration = if let s = buildStart, let e = buildEnd {
            e.timeIntervalSince(s)
        } else {
            0.0
        }
        let instDuration: Double? = if let s = installStart, let e = installEnd {
            e.timeIntervalSince(s)
        } else {
            nil
        }

        let estimatedCost = ModelPricing.estimate(
            model: model,
            inputTokens: tokenUsage.inputTokens,
            outputTokens: tokenUsage.outputTokens,
            cacheReadTokens: tokenUsage.cacheReadTokens,
            cacheWriteTokens: tokenUsage.cacheWriteTokens
        )

        return GenerationTelemetry(
            id: id,
            pluginId: pluginId,
            versionNumber: versionNumber,
            generationType: generationType,
            agent: agent,
            model: model,
            originalPrompt: originalPrompt,
            enhancedPrompt: enhancedPrompt,
            systemPromptVersion: systemPromptVersion,
            startedAt: startedAt,
            enhancerDuration: nil,
            generationDuration: genDuration,
            auditDuration: auditDur,
            buildDuration: bldDuration,
            installDuration: instDuration,
            totalDuration: now.timeIntervalSince(startedAt),
            inputTokens: tokenUsage.inputTokens > 0 ? tokenUsage.inputTokens : nil,
            outputTokens: tokenUsage.outputTokens > 0 ? tokenUsage.outputTokens : nil,
            cacheReadTokens: tokenUsage.cacheReadTokens > 0 ? tokenUsage.cacheReadTokens : nil,
            cacheWriteTokens: tokenUsage.cacheWriteTokens > 0 ? tokenUsage.cacheWriteTokens : nil,
            totalTokens: tokenUsage.totalTokens > 0 ? tokenUsage.totalTokens : nil,
            estimatedCostUSD: estimatedCost > 0 ? estimatedCost : nil,
            buildAttempts: buildLogs.count,
            buildLogs: buildLogs,
            outcome: outcome,
            failureStage: failureStage,
            failureMessage: failureMessage,
            failureDetails: failureDetails,
            pluginType: pluginType,
            format: format,
            channelLayout: channelLayout,
            presetCount: presetCount,
            macOSVersion: macOSVersion,
            cpuArchitecture: cpuArchitecture,
            xcodeVersion: xcodeVersion,
            juceVersion: juceVersion,
            agentCLIVersion: agentCLIVersion
        )
    }
}

// MARK: - Model pricing

enum ModelPricing {
    /// Returns estimated cost in USD. Prices per million tokens.
    static func estimate(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int
    ) -> Double {
        let rates: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) = switch model {
        case let m where m.contains("opus"):
            (15.0, 75.0, 1.5, 18.75)
        case let m where m.contains("sonnet"):
            (3.0, 15.0, 0.3, 3.75)
        case let m where m.contains("haiku"):
            (0.25, 1.25, 0.025, 0.3)
        case let m where m.contains("o3"):
            (2.0, 8.0, 0.5, 2.5)
        case let m where m.contains("o4-mini"):
            (1.1, 4.4, 0.275, 1.375)
        case let m where m.contains("gpt-4o"):
            (2.5, 10.0, 1.25, 3.125)
        case let m where m.contains("codex"):
            (2.0, 8.0, 0.5, 2.5)
        default:
            (3.0, 15.0, 0.3, 3.75) // default to sonnet-tier
        }

        let input = Double(inputTokens) / 1_000_000 * rates.input
        let output = Double(outputTokens) / 1_000_000 * rates.output
        let cacheRead = Double(cacheReadTokens) / 1_000_000 * rates.cacheRead
        let cacheWrite = Double(cacheWriteTokens) / 1_000_000 * rates.cacheWrite
        return input + output + cacheRead + cacheWrite
    }
}
