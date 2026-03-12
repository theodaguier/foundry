import SwiftUI

enum GenerationStep: Int, CaseIterable {
    case preparingProject = 0
    case generatingDSP
    case generatingUI
    case compiling
    case installing

    var label: String {
        switch self {
        case .preparingProject: "Preparing project..."
        case .generatingDSP: "Generating DSP..."
        case .generatingUI: "Generating UI..."
        case .compiling: "Compiling..."
        case .installing: "Installing..."
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
    @State private var previousStep: GenerationStep = .preparingProject

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text(pipeline.currentStep.label)
                    .font(.title3)
                    .fontWeight(.medium)

                Text(config.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if pipeline.buildAttempt > 1 {
                    Text("Build attempt \(pipeline.buildAttempt)/3")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: 480)

            ProgressView(value: progress)
                .tint(.accentColor)
                .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(GenerationStep.allCases, id: \.self) { step in
                    if step.rawValue <= pipeline.currentStep.rawValue {
                        HStack(spacing: 6) {
                            if completedSteps.contains(step.rawValue) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                    .frame(width: 12)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 12)
                            }

                            Text(step.label.replacingOccurrences(of: "...", with: ""))
                                .font(.caption)
                                .foregroundStyle(step == pipeline.currentStep ? .primary : .tertiary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .navigationTitle("Building")
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
            pipeline.run(config: config, appState: appState)
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: pipeline.currentStep) { oldValue, newValue in
            // Mark old step as completed when we advance
            if newValue.rawValue > oldValue.rawValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    completedSteps.insert(oldValue.rawValue)
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

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
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
