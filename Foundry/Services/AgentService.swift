import Foundation

// MARK: - Agent event (agent-agnostic)

enum AgentEvent: Sendable {
    case toolUse(tool: String, filePath: String?, detail: String?)
    case toolResult(tool: String, output: String)
    case text(String)
    case result(success: Bool)
    case error(String)
}

// MARK: - Agent run result

struct AgentRunResult: Sendable {
    var success: Bool
    var output: String
    var error: String?
}

// MARK: - Agent resolver

/// Dispatches agent calls to the correct service based on `GenerationAgent` + `AgentModel`.
enum AgentResolver {

    static func run(
        agent: GenerationAgent,
        model: AgentModel,
        prompt: String,
        projectDir: URL,
        isRefine: Bool = false,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        switch agent {
        case .claudeCode:
            return await ClaudeCodeService.agentRun(prompt: prompt, projectDir: projectDir, model: model, mode: isRefine ? .refine : .generate, onEvent: onEvent)
        case .codex:
            return await CodexService.run(prompt: prompt, projectDir: projectDir, model: model, onEvent: onEvent)
        }
    }

    static func fix(
        agent: GenerationAgent,
        model: AgentModel,
        errors: String,
        projectDir: URL,
        attempt: Int,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        switch agent {
        case .claudeCode:
            return await ClaudeCodeService.agentFix(errors: errors, projectDir: projectDir, attempt: attempt, model: model, onEvent: onEvent)
        case .codex:
            return await CodexService.fix(errors: errors, projectDir: projectDir, attempt: attempt, model: model, onEvent: onEvent)
        }
    }

    static func generatePluginName(
        agent: GenerationAgent,
        prompt: String,
        existingNames: Set<String>
    ) async -> String {
        switch agent {
        case .claudeCode:
            return await ClaudeCodeService.generatePluginName(prompt: prompt, existingNames: existingNames)
        case .codex:
            return await CodexService.generatePluginName(prompt: prompt, existingNames: existingNames)
        }
    }

    static func audit(
        agent: GenerationAgent,
        model: AgentModel,
        projectDir: URL,
        userIntent: String,
        pluginType: String,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        switch agent {
        case .claudeCode:
            return await ClaudeCodeService.agentAudit(projectDir: projectDir, userIntent: userIntent, pluginType: pluginType, model: model, onEvent: onEvent)
        case .codex:
            return await CodexService.audit(projectDir: projectDir, userIntent: userIntent, pluginType: pluginType, model: model, onEvent: onEvent)
        }
    }
}
