import SwiftUI

struct RefineProgressView: View {
    @Environment(AppState.self) private var appState
    let config: RefineConfig

    @State private var pipeline = GenerationPipeline()
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var completedSteps: Set<Int> = []

    private var refineSteps: [GenerationStep] {
        [.generatingDSP, .generatingUI, .compiling, .installing]
    }

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

                GlassEffectContainer(spacing: 1) {
                    VStack(spacing: 1) {
                        ForEach(refineSteps, id: \.self) { step in
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
                            .glassEffect(.regular, in: .rect(cornerRadius: 6))
                        }
                    }
                }
            }
            .frame(maxWidth: 440)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Refining")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(formattedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    pipeline.cancel()
                    timer?.invalidate()
                    appState.popToRoot()
                }
                .buttonStyle(.glass)
            }
        }
        .onAppear {
            startTimer()
            pipeline.refine(config: config, appState: appState)
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
        RefineProgressView(config: RefineConfig(
            plugin: Plugin.samplePlugins[0],
            modification: "Add a low-pass filter with resonance"
        ))
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
