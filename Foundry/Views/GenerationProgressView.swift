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

                StepListView(
                    steps: GenerationStep.allCases,
                    currentStep: pipeline.currentStep,
                    completedSteps: completedSteps,
                    buildAttempt: pipeline.buildAttempt
                )
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
                    appState.popToRoot()
                }
            }
        }
        .onAppear {
            pipeline.run(config: config, appState: appState)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
        .onChange(of: pipeline.currentStep) { oldValue, newValue in
            if newValue.rawValue > oldValue.rawValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = completedSteps.insert(oldValue.rawValue)
                }
            }
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
}

#Preview {
    NavigationStack {
        GenerationProgressView(config: GenerationConfig(prompt: "A warm analog synth"))
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
