import SwiftUI

struct RefineProgressView: View {
    @Environment(AppState.self) private var appState
    let config: RefineConfig

    private var build: ActiveBuild? { appState.activeBuild }
    private let refineSteps: [GenerationStep] = [.generatingDSP, .generatingUI, .compiling, .installing]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let build {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(build.pipeline.currentStep.label)
                            .font(.title2)
                            .fontWeight(.medium)
                            .contentTransition(.numericText())

                        Text(config.modification)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: build.progress)
                            .tint(.accentColor)

                        HStack {
                            if build.pipeline.buildAttempt > 1 {
                                Text("Build attempt \(build.pipeline.buildAttempt)/3")
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
                        currentStep: build.pipeline.currentStep,
                        completedSteps: build.completedSteps,
                        buildAttempt: build.pipeline.buildAttempt
                    )
                }
                .frame(maxWidth: 440)
            }

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
                    build?.pipeline.cancel()
                    build?.stopTimer()
                    appState.activeBuild = nil
                    appState.buildProgress = 0
                    appState.popToRoot()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.popToRoot()
                } label: {
                    Label("Back to Library", systemImage: "square.grid.2x2")
                }
                .help("Continue in background")
            }
        }
        .onAppear {
            if appState.activeBuild == nil {
                let newBuild = ActiveBuild(kind: .refinement(config))
                appState.activeBuild = newBuild
                newBuild.pipeline.refine(config: config, appState: appState)
                newBuild.startTimer()
            }
            appState.activeBuild?.isViewingProgress = true
        }
        .onDisappear {
            appState.activeBuild?.isViewingProgress = false
        }
        .onChange(of: build?.pipeline.currentStep) { oldValue, newValue in
            guard let oldValue, let newValue, let build else { return }
            build.updateStep(from: oldValue, to: newValue)
            appState.buildProgress = build.progress
        }
    }

    private var currentStepIndex: Int {
        guard let build else { return 0 }
        return refineSteps.firstIndex(of: build.pipeline.currentStep) ?? 0
    }

    private var formattedTime: String {
        let seconds = build?.elapsedSeconds ?? 0
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
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
