import SwiftUI

// MARK: - Generation Step

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

    var terminalLabel: String {
        switch self {
        case .preparingProject: "PREPARING PROJECT"
        case .generatingDSP: "GENERATING DSP"
        case .generatingUI: "GENERATING UI"
        case .compiling: "COMPILING"
        case .installing: "INSTALLING"
        }
    }

    var logLabel: String { terminalLabel }

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

// MARK: - Generation Progress View

struct GenerationProgressView: View {
    @Environment(AppState.self) private var appState
    let config: GenerationConfig

    private var build: ActiveBuild? { appState.activeBuild }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(maxWidth: .infinity)

            if build?.showConsole == true, let build {
                Divider()

                TerminalView(
                    title: "Build Log",
                    logLines: build.pipeline.logLines,
                    elapsedTime: formattedTime,
                    streamingText: build.pipeline.streamingText
                )
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Building")
        .navigationBarBackButtonHidden(true)
        .toolbar {
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
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: Binding(
                    get: { build?.showConsole ?? false },
                    set: { newValue in withAnimation { build?.showConsole = newValue } }
                )) {
                    Label("Console", systemImage: "terminal")
                }
                .toggleStyle(.button)
            }
        }
        .onAppear {
            // Only start a new build if there isn't one already running for this config
            if appState.activeBuild == nil {
                let newBuild = ActiveBuild(kind: .generation(config))
                appState.activeBuild = newBuild
                appState.buildProgress = 0
                newBuild.pipeline.run(config: config, appState: appState)
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

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                if let build {
                    GenerationStepList(
                        currentStep: build.pipeline.currentStep,
                        completedSteps: build.completedSteps
                    )
                    .frame(maxWidth: 360)

                    ProgressView(value: build.progress)
                        .tint(.accentColor)
                        .frame(maxWidth: 360)
                }
            }

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let seconds = build?.elapsedSeconds ?? 0
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Generation Step List

struct GenerationStepList: View {
    let currentStep: GenerationStep
    let completedSteps: Set<Int>

    var body: some View {
        VStack(spacing: 0) {
            ForEach(GenerationStep.allCases, id: \.self) { step in
                GenerationStepRow(
                    step: step,
                    isActive: currentStep == step,
                    isDone: completedSteps.contains(step.rawValue)
                )
            }
        }
    }
}

// MARK: - Generation Step Row

struct GenerationStepRow: View {
    let step: GenerationStep
    let isActive: Bool
    let isDone: Bool

    private var isPending: Bool { !isDone && !isActive }

    var body: some View {
        HStack(spacing: 10) {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .frame(width: 20)
            } else if isActive {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.quaternary)
                    .frame(width: 20)
            }

            Text(step.label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isPending ? .tertiary : .primary)

            Spacer()

            if isDone {
                Text("Done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GenerationProgressView(config: GenerationConfig(prompt: "A warm analog synth with detuned oscillators"))
    }
    .environment({
        let s = AppState()
        s.plugins = Plugin.samplePlugins
        return s
    }())
    .preferredColorScheme(.dark)
}
