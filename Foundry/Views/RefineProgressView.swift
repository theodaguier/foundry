import SwiftUI

struct RefineProgressView: View {
    @Environment(AppState.self) private var appState
    let config: RefineConfig

    @State private var pipeline = GenerationPipeline()
    @State private var elapsedSeconds: Int = 0
    @State private var completedSteps: Set<Int> = []

    private let refineSteps: [GenerationStep] = [.generatingDSP, .generatingUI, .compiling, .installing]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pipeline.currentStep.label)
                        .font(.title2)
                        .fontWeight(.medium)
                        .contentTransition(.numericText())

                    Text(config.modification)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

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

                        Text("Step \(currentStepIndex + 1) of \(refineSteps.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                StepListView(
                    steps: refineSteps,
                    currentStep: pipeline.currentStep,
                    completedSteps: completedSteps,
                    buildAttempt: pipeline.buildAttempt
                )
            }
            .frame(maxWidth: 440)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Refining")
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
            pipeline.refine(config: config, appState: appState)
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

    private var currentStepIndex: Int {
        refineSteps.firstIndex(of: pipeline.currentStep) ?? 0
    }

    private var progress: Double {
        Double(currentStepIndex) / Double(refineSteps.count)
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        RefineProgressView(config: RefineConfig(
            plugin: Plugin.samplePlugins[0],
            modification: "Add a low-pass filter with resonance"
        ))
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
