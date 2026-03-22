import Foundation

/// Fetches and caches model catalogs from provider APIs (Anthropic, OpenAI).
/// Falls back to bundled `models.json` when APIs are unreachable.
enum ModelCatalogService {

    private static let cacheTTL: TimeInterval = 24 * 60 * 60 // 24h

    private static var cacheFile: URL {
        FoundryPaths.modelsCacheFile
    }

    // MARK: - Public

    /// Loads providers: disk cache first (fast), then returns.
    /// Call `refresh()` separately to update from APIs in the background.
    static func loadCached() -> [AgentProvider]? {
        guard let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(CachedCatalog.self, from: data) else {
            return nil
        }
        return cache.providers
    }

    /// Whether the cache is stale (older than 24h or missing).
    static var cacheIsStale: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date else {
            return true
        }
        return Date().timeIntervalSince(modified) > cacheTTL
    }

    /// Fetches models from provider APIs, filters them, and updates the disk cache.
    /// Returns the merged providers, or `nil` if all fetches failed.
    @discardableResult
    static func refresh() async -> [AgentProvider]? {
        async let anthropicResult = AnthropicModelFetcher.fetchModels()
        async let openAIResult = OpenAIModelFetcher.fetchModels()

        let anthropicModels = await anthropicResult
        let openAIModels = await openAIResult

        var providers: [AgentProvider] = []

        if let models = anthropicModels, !models.isEmpty {
            providers.append(AgentProvider(
                id: "claude-code",
                name: "Claude Code",
                icon: "ProviderAnthropic",
                command: "claude",
                models: models
            ))
        }

        if let models = openAIModels, !models.isEmpty {
            providers.append(AgentProvider(
                id: "codex",
                name: "Codex",
                icon: "ProviderOpenAI",
                command: "codex",
                models: models
            ))
        }

        guard !providers.isEmpty else { return nil }

        // Save to disk cache
        let cache = CachedCatalog(providers: providers, lastUpdated: Date())
        if let data = try? JSONEncoder().encode(cache) {
            let dir = cacheFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: .atomic)
        }

        return providers
    }

    /// Timestamp of the last successful refresh, or `nil` if no cache exists.
    static var lastUpdated: Date? {
        guard let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(CachedCatalog.self, from: data) else {
            return nil
        }
        return cache.lastUpdated
    }

    // MARK: - Cache model

    private struct CachedCatalog: Codable {
        let providers: [AgentProvider]
        let lastUpdated: Date
    }
}

// MARK: - Anthropic model fetcher

enum AnthropicModelFetcher {

    /// Fetches models from the Anthropic API using the API key from the environment.
    static func fetchModels() async -> [AgentModel]? {
        guard let apiKey = resolveAPIKey() else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return nil
        }

        return models
            .compactMap { parseAnthropicModel($0) }
            .filter { isCodeModel($0.id) }
            .sorted { modelPriority($0.id) < modelPriority($1.id) }
    }

    private static func resolveAPIKey() -> String? {
        // Check environment (set by Claude Code CLI or user)
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }

    private static func parseAnthropicModel(_ json: [String: Any]) -> AgentModel? {
        guard let id = json["id"] as? String else { return nil }

        let displayName = ModelDisplayInfo.name(for: id) ?? formatModelName(id)
        let subtitle = ModelDisplayInfo.subtitle(for: id) ?? "Anthropic model"
        let flag = cliFlag(for: id)

        return AgentModel(
            id: id,
            name: displayName,
            subtitle: subtitle,
            flag: flag,
            default: flag == "sonnet"
        )
    }

    /// Maps API model ID to Claude Code CLI flag.
    private static func cliFlag(for modelId: String) -> String {
        if modelId.contains("opus") { return "opus" }
        if modelId.contains("haiku") { return "haiku" }
        return "sonnet" // default for sonnet variants
    }

    private static func isCodeModel(_ id: String) -> Bool {
        id.hasPrefix("claude-") && !id.contains("embedding")
    }

    private static func modelPriority(_ id: String) -> Int {
        if id.contains("opus") { return 0 }
        if id.contains("sonnet") { return 1 }
        if id.contains("haiku") { return 2 }
        return 3
    }

    private static func formatModelName(_ id: String) -> String {
        // "claude-sonnet-4-5-20250514" → "Claude Sonnet 4.5"
        id.replacingOccurrences(of: "claude-", with: "Claude ")
            .replacingOccurrences(of: "-20\\d{6}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - OpenAI model fetcher

enum OpenAIModelFetcher {

    static func fetchModels() async -> [AgentModel]? {
        guard let apiKey = resolveAPIKey() else { return nil }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return nil
        }

        return models
            .compactMap { parseOpenAIModel($0) }
            .filter { isCodeModel($0.id) }
            .sorted { modelPriority($0.id) < modelPriority($1.id) }
    }

    private static func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }

    private static func parseOpenAIModel(_ json: [String: Any]) -> AgentModel? {
        guard let id = json["id"] as? String else { return nil }

        let displayName = ModelDisplayInfo.name(for: id) ?? id
        let subtitle = ModelDisplayInfo.subtitle(for: id) ?? "OpenAI model"

        return AgentModel(
            id: id,
            name: displayName,
            subtitle: subtitle,
            flag: id,
            default: id == "o3"
        )
    }

    private static func isCodeModel(_ id: String) -> Bool {
        let include = ["codex-", "o1", "o3", "o4", "gpt-4"]
        let exclude = ["dall-e", "tts-", "whisper-", "text-embedding-", "audio", "realtime", "moderation"]

        let matchesInclude = include.contains { id.hasPrefix($0) }
        let matchesExclude = exclude.contains { id.contains($0) }

        return matchesInclude && !matchesExclude
    }

    private static func modelPriority(_ id: String) -> Int {
        if id.hasPrefix("o4") { return 0 }
        if id.hasPrefix("o3") { return 1 }
        if id.hasPrefix("o1") { return 2 }
        if id.hasPrefix("gpt-4") { return 3 }
        if id.hasPrefix("codex-") { return 4 }
        return 5
    }
}

// MARK: - Display info mapping

/// Local mapping of model IDs to human-readable names and subtitles.
/// Updated per app release — API doesn't provide these.
private enum ModelDisplayInfo {

    static func name(for id: String) -> String? {
        for (pattern, name) in names {
            if id.contains(pattern) { return name }
        }
        return nil
    }

    static func subtitle(for id: String) -> String? {
        for (pattern, sub) in subtitles {
            if id.contains(pattern) { return sub }
        }
        return nil
    }

    private static let names: [(String, String)] = [
        // Anthropic
        ("claude-opus-4", "Claude Opus 4"),
        ("claude-sonnet-4", "Claude Sonnet 4"),
        ("claude-haiku-4", "Claude Haiku 4"),
        ("claude-3-5-sonnet", "Claude 3.5 Sonnet"),
        ("claude-3-5-haiku", "Claude 3.5 Haiku"),
        ("claude-3-opus", "Claude 3 Opus"),
        // OpenAI
        ("o4-mini", "o4-mini"),
        ("o4", "o4"),
        ("o3-mini", "o3-mini"),
        ("o3", "o3"),
        ("o1-mini", "o1-mini"),
        ("o1", "o1"),
        ("gpt-4o-mini", "GPT-4o mini"),
        ("gpt-4o", "GPT-4o"),
        ("gpt-4-turbo", "GPT-4 Turbo"),
        ("gpt-4", "GPT-4"),
        ("codex-mini", "Codex Mini"),
    ]

    private static let subtitles: [(String, String)] = [
        // Anthropic
        ("opus", "Most powerful"),
        ("sonnet", "Fast & capable"),
        ("haiku", "Fastest"),
        // OpenAI
        ("o4-mini", "Fast & affordable"),
        ("o4", "Reasoning"),
        ("o3-mini", "Fast reasoning"),
        ("o3", "Reasoning"),
        ("o1-mini", "Fast reasoning"),
        ("o1", "Reasoning"),
        ("gpt-4o-mini", "Fast & affordable"),
        ("gpt-4o", "Fast & capable"),
        ("gpt-4-turbo", "Powerful"),
        ("gpt-4", "Powerful"),
        ("codex-mini", "Code generation"),
    ]
}
