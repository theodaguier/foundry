import Foundation
import Supabase

enum TelemetryService {

    // MARK: - Storage path

    /// `~/Library/Application Support/Foundry/telemetry/<YYYY-MM>/<id>.json`
    static func directory(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: date)
        return FoundryPaths.telemetryDirectory.appendingPathComponent(month, isDirectory: true)
    }

    static func filePath(for telemetry: GenerationTelemetry) -> URL {
        directory(for: telemetry.startedAt)
            .appendingPathComponent("\(telemetry.id.uuidString).json")
    }

    // MARK: - Write (local + remote)

    static func save(_ telemetry: GenerationTelemetry) {
        // 1. Save locally
        let dir = directory(for: telemetry.startedAt)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(telemetry) else { return }
        let path = filePath(for: telemetry)
        try? data.write(to: path)

        // 2. Sync to Supabase (fire-and-forget)
        Task { await syncToSupabase(telemetry) }
    }

    // MARK: - Supabase sync

    @MainActor
    private static func syncToSupabase(_ telemetry: GenerationTelemetry) async {
        let client = AuthService.shared.client
        guard let userId = try? await client.auth.session.user.id else {
            print("[Telemetry] Not authenticated — skipping Supabase sync")
            return
        }

        let row = TelemetryRow(telemetry: telemetry, userId: userId)

        do {
            try await client.from("generation_telemetry")
                .insert(row)
                .execute()
        } catch {
            print("[Telemetry] Supabase sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read (local)

    static func load(id: UUID) -> GenerationTelemetry? {
        let baseDir = FoundryPaths.telemetryDirectory
        guard let months = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else { return nil }

        let filename = "\(id.uuidString).json"
        for monthDir in months {
            let file = monthDir.appendingPathComponent(filename)
            if let telemetry = loadFile(at: file) {
                return telemetry
            }
        }
        return nil
    }

    static func loadForPlugin(pluginId: UUID) -> [GenerationTelemetry] {
        loadAll().filter { $0.pluginId == pluginId }
    }

    static func loadAll() -> [GenerationTelemetry] {
        let baseDir = FoundryPaths.telemetryDirectory
        guard let months = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var results: [GenerationTelemetry] = []
        for monthDir in months {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: monthDir, includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where file.pathExtension == "json" {
                if let t = loadFile(at: file) {
                    results.append(t)
                }
            }
        }
        return results.sorted { $0.startedAt > $1.startedAt }
    }

    private static func loadFile(at url: URL) -> GenerationTelemetry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GenerationTelemetry.self, from: data)
    }

    // MARK: - Environment helpers

    static func detectXcodeVersion() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.components(separatedBy: .newlines).first
            }
        } catch {}
        return nil
    }

    static func detectAgentCLIVersion(agent: GenerationAgent) -> String? {
        let command: String
        switch agent {
        case .claudeCode: command = "claude"
        case .codex: command = "codex"
        }
        guard let path = DependencyChecker.resolveCommandPath(command) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.environment = DependencyChecker.shellEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        return nil
    }
}

// MARK: - Supabase row model

/// Maps `GenerationTelemetry` to the Supabase table columns (snake_case).
private struct TelemetryRow: Encodable {
    let id: UUID
    let user_id: UUID
    let plugin_id: UUID?
    let version_number: Int?
    let agent: String
    let model: String
    let original_prompt: String
    let enhanced_prompt: String?
    let system_prompt_version: String?
    let started_at: Date
    let enhancer_duration: Double?
    let generation_duration: Double
    let audit_duration: Double?
    let build_duration: Double
    let install_duration: Double?
    let total_duration: Double
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_tokens: Int?
    let cache_write_tokens: Int?
    let total_tokens: Int?
    let estimated_cost_usd: Double?
    let build_attempts: Int
    let build_logs: [BuildAttemptLog]
    let outcome: String
    let failure_stage: String?
    let failure_message: String?
    let failure_details: String?
    let plugin_type: String
    let format: String
    let channel_layout: String
    let preset_count: Int
    let macos_version: String?
    let cpu_architecture: String?
    let xcode_version: String?
    let juce_version: String?
    let agent_cli_version: String?

    init(telemetry t: GenerationTelemetry, userId: UUID) {
        id = t.id
        user_id = userId
        plugin_id = t.pluginId
        version_number = t.versionNumber
        agent = t.agent.rawValue
        model = t.model
        original_prompt = t.originalPrompt
        enhanced_prompt = t.enhancedPrompt
        system_prompt_version = t.systemPromptVersion
        started_at = t.startedAt
        enhancer_duration = t.enhancerDuration
        generation_duration = t.generationDuration
        audit_duration = t.auditDuration
        build_duration = t.buildDuration
        install_duration = t.installDuration
        total_duration = t.totalDuration
        input_tokens = t.inputTokens
        output_tokens = t.outputTokens
        cache_read_tokens = t.cacheReadTokens
        cache_write_tokens = t.cacheWriteTokens
        total_tokens = t.totalTokens
        estimated_cost_usd = t.estimatedCostUSD
        build_attempts = t.buildAttempts
        build_logs = t.buildLogs
        outcome = t.outcome.rawValue
        failure_stage = t.failureStage?.rawValue
        failure_message = t.failureMessage
        failure_details = t.failureDetails
        plugin_type = t.pluginType.rawValue
        format = t.format.rawValue
        channel_layout = t.channelLayout.rawValue
        preset_count = t.presetCount
        macos_version = t.macOSVersion
        cpu_architecture = t.cpuArchitecture
        xcode_version = t.xcodeVersion
        juce_version = t.juceVersion
        agent_cli_version = t.agentCLIVersion
    }
}
