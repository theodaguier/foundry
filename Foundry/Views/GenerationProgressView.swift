import SwiftUI

enum GenerationStep: Int, CaseIterable {
    case preparingProject = 0
    case generatingDSP
    case generatingUI
    case compiling
    case installing

    var label: String {
        switch self {
        case .preparingProject: "Preparing project"
        case .generatingDSP: "Generating DSP"
        case .generatingUI: "Generating UI"
        case .compiling: "Compiling"
        case .installing: "Installing"
        }
    }

    var icon: String {
        switch self {
        case .preparingProject: "folder"
        case .generatingDSP: "waveform"
        case .generatingUI: "slider.horizontal.3"
        case .compiling: "hammer"
        case .installing: "arrow.down.to.line"
        }
    }
}

struct GenerationProgressView: View {
    @Environment(AppState.self) private var appState
    let config: GenerationConfig

    @State private var pipeline = GenerationPipeline()
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var completedSteps: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                // Current step headline
                VStack(alignment: .leading, spacing: 6) {
                    Text(pipeline.currentStep.label)
                        .font(.title2)
                        .fontWeight(.medium)
                        .contentTransition(.numericText())

                    Text(config.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.accentColor)

                    HStack {
                        if pipeline.buildAttempt > 1 {
                            Text("Build attempt \(pipeline.buildAttempt)/3")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Text("Step \(pipeline.currentStep.rawValue + 1) of \(GenerationStep.allCases.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Step list
                VStack(spacing: 2) {
                    ForEach(GenerationStep.allCases, id: \.self) { step in
                        HStack(spacing: 10) {
                            stepIndicator(for: step)
                                .frame(width: 16)

                            Image(systemName: step.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(stepColor(for: step))
                                .frame(width: 16)

                            Text(step.label)
                                .font(.subheadline)
                                .foregroundStyle(stepColor(for: step))

                            Spacer()

                            if completedSteps.contains(step.rawValue) {
                                Text("Done")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            step == pipeline.currentStep
                                ? Color.accentColor.opacity(0.06)
                                : Color.clear,
                            in: .rect(cornerRadius: 6)
                        )
                    }
                }
                .padding(4)
                .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 10))
            }
            .frame(maxWidth: 440)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Building")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(formattedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    pipeline.cancel()
                    timer?.invalidate()
                    appState.popToRoot()
                }
            }
        }
        .onAppear {
            startTimer()
            pipeline.run(config: config, appState: appState)
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: pipeline.currentStep) { oldValue, newValue in
            if newValue.rawValue > oldValue.rawValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = completedSteps.insert(oldValue.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIndicator(for step: GenerationStep) -> some View {
        if completedSteps.contains(step.rawValue) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        } else if step == pipeline.currentStep {
            ProgressView()
                .controlSize(.mini)
        } else if step.rawValue > pipeline.currentStep.rawValue {
            Circle()
                .fill(.quaternary)
                .frame(width: 6, height: 6)
        } else {
            EmptyView()
        }
    }

    private func stepColor(for step: GenerationStep) -> some ShapeStyle {
        if completedSteps.contains(step.rawValue) {
            return .tertiary
        } else if step == pipeline.currentStep {
            return .primary
        } else {
            return .quaternary
        }
    }

    private var progress: Double {
        Double(pipeline.currentStep.rawValue) / Double(GenerationStep.allCases.count)
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 1
            }
        }
    }
}

#Preview {
    NavigationStack {
        GenerationProgressView(config: GenerationConfig(prompt: "A warm analog synth"))
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
