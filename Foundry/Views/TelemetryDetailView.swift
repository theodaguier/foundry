import SwiftUI

struct TelemetryDetailView: View {
    let telemetry: GenerationTelemetry

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                Divider()
                agentSection
                Divider()
                promptSection
                Divider()
                timingSection
                Divider()
                tokenSection
                if !telemetry.buildLogs.isEmpty {
                    Divider()
                    buildSection
                }
                if telemetry.outcome != .success {
                    Divider()
                    errorSection
                }
                Divider()
                environmentSection
            }
        }
        .frame(width: 480)
        .background(FoundryTheme.Colors.background)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: telemetry.outcome == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(telemetry.outcome == .success ? .green : .red)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(telemetry.outcome == .success ? "Generated" : "Failed at \(failureStageLabel)")
                    .font(FoundryTheme.Fonts.azeretMono(12))
                    .foregroundStyle(.primary)
                Text(formatDuration(telemetry.totalDuration) + " total")
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }

            Spacer()

            Text(telemetry.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(FoundryTheme.Fonts.azeretMono(9))
                .foregroundStyle(FoundryTheme.Colors.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Agent

    private var agentSection: some View {
        VStack(spacing: 0) {
            TelemetryRow(label: "AGENT", value: "\(telemetry.agent.displayName) (\(telemetry.model))")
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(spacing: 0) {
            TelemetryRow(label: "PROMPT", value: telemetry.originalPrompt)
            if let enhanced = telemetry.enhancedPrompt {
                TelemetrySeparator()
                TelemetryRow(label: "ENHANCED", value: enhanced)
            }
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(spacing: 0) {
            TelemetryLabel(text: "TIMING")

            TelemetryRow(label: "Generation", value: formatDuration(telemetry.generationDuration))
            if let auditDuration = telemetry.auditDuration {
                TelemetrySeparator()
                TelemetryRow(label: "Audit", value: formatDuration(auditDuration))
            }
            TelemetrySeparator()
            HStack {
                TelemetryRow(label: "Build", value: formatDuration(telemetry.buildDuration))
                if telemetry.buildAttempts > 1 {
                    Text("(\(telemetry.buildAttempts) attempts)")
                        .font(FoundryTheme.Fonts.azeretMono(9))
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                        .padding(.trailing, 20)
                }
            }
            if let installDuration = telemetry.installDuration {
                TelemetrySeparator()
                TelemetryRow(label: "Install", value: formatDuration(installDuration))
            }
        }
    }

    // MARK: - Tokens

    private var tokenSection: some View {
        VStack(spacing: 0) {
            TelemetryLabel(text: "TOKENS")

            if let input = telemetry.inputTokens {
                TelemetryRow(label: "Input", value: formatNumber(input))
            }
            if let output = telemetry.outputTokens {
                TelemetrySeparator()
                TelemetryRow(label: "Output", value: formatNumber(output))
            }
            if let cache = telemetry.cacheReadTokens {
                TelemetrySeparator()
                TelemetryRow(label: "Cache hit", value: formatNumber(cache))
            }
            if let cost = telemetry.estimatedCostUSD {
                TelemetrySeparator()
                TelemetryRow(label: "Estimated", value: String(format: "$%.2f", cost))
            }
        }
    }

    // MARK: - Build attempts

    private var buildSection: some View {
        VStack(spacing: 0) {
            TelemetryLabel(text: "BUILD")

            ForEach(Array(telemetry.buildLogs.enumerated()), id: \.offset) { index, attempt in
                if index > 0 { TelemetrySeparator() }
                HStack(spacing: 8) {
                    Image(systemName: attempt.success ? "checkmark" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(attempt.success ? .green : .red)
                        .frame(width: 12)

                    Text("Attempt \(attempt.attemptNumber)")
                        .font(FoundryTheme.Fonts.azeretMono(10))
                        .foregroundStyle(FoundryTheme.Colors.textSecondary)

                    Text(formatDuration(attempt.duration))
                        .font(FoundryTheme.Fonts.azeretMono(10))
                        .foregroundStyle(FoundryTheme.Colors.textMuted)

                    Spacer()

                    if let errors = attempt.errors, !attempt.success {
                        Text(errors.components(separatedBy: .newlines).first ?? "")
                            .font(FoundryTheme.Fonts.azeretMono(9))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                            .frame(maxWidth: 200, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Error

    private var errorSection: some View {
        VStack(spacing: 0) {
            TelemetryLabel(text: "ERROR")

            if let msg = telemetry.failureMessage {
                Text(msg)
                    .font(FoundryTheme.Fonts.azeretMono(10))
                    .foregroundStyle(.red.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            if let details = telemetry.failureDetails {
                Text(details)
                    .font(FoundryTheme.Fonts.azeretMono(9))
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        VStack(spacing: 0) {
            TelemetryLabel(text: "ENVIRONMENT")

            let parts = [
                "macOS \(telemetry.macOSVersion)",
                telemetry.cpuArchitecture == "arm64" ? "Apple Silicon" : "Intel",
                telemetry.xcodeVersion,
                telemetry.agentCLIVersion.map { "\(telemetry.agent.displayName) \($0)" },
                telemetry.juceVersion.map { "JUCE \($0)" }
            ].compactMap { $0 }

            Text(parts.joined(separator: " · "))
                .font(FoundryTheme.Fonts.azeretMono(10))
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var failureStageLabel: String {
        switch telemetry.failureStage {
        case .assembly: "Assembly"
        case .promptEnhancement: "Prompt Enhancement"
        case .generation: "Generation"
        case .qualityEnforcement: "Quality Check"
        case .build: "Build"
        case .install: "Install"
        case .smokeTest: "Smoke Test"
        case nil: telemetry.outcome.rawValue
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Components

private struct TelemetryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(FoundryTheme.Fonts.azeretMono(9))
                .tracking(1.0)
                .foregroundStyle(FoundryTheme.Colors.textMuted)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(FoundryTheme.Fonts.azeretMono(10))
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}

private struct TelemetryLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.Fonts.azeretMono(9))
            .tracking(1.2)
            .foregroundStyle(FoundryTheme.Colors.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct TelemetrySeparator: View {
    var body: some View {
        Rectangle()
            .fill(FoundryTheme.Colors.border.opacity(0.5))
            .frame(height: 1)
            .padding(.leading, 116)
    }
}
