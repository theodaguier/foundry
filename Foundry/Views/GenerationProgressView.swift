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

    @State private var pipeline = GenerationPipeline()
    @State private var elapsedSeconds: Int = 0
    @State private var completedSteps: Set<Int> = []
    @State private var highWaterStep: Int = 0

    @State private var showConsole = false

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(maxWidth: .infinity)

            if showConsole {
                Divider()

                TerminalView(
                    title: "Build Log",
                    logLines: pipeline.logLines,
                    elapsedTime: formattedTime,
                    streamingText: pipeline.streamingText
                )
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Building")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    pipeline.cancel()
                    appState.popToRoot()
                }
            }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: Binding(
                    get: { showConsole },
                    set: { newValue in withAnimation { showConsole = newValue } }
                )) {
                    Label("Console", systemImage: "terminal")
                }
                .toggleStyle(.button)
            }
        }
        .onAppear {
            pipeline.run(config: config, appState: appState)
            appState.buildProgress = 0
        }
        .onDisappear {
            appState.buildProgress = 0
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
        .onChange(of: pipeline.currentStep) { oldValue, newValue in
            if newValue.rawValue > highWaterStep {
                highWaterStep = newValue.rawValue
                _ = completedSteps.insert(oldValue.rawValue)
            }
            appState.buildProgress = progress
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                GenerationStepList(
                    currentStep: pipeline.currentStep,
                    completedSteps: completedSteps
                )
                .frame(maxWidth: 360)

                ProgressView(value: progress)
                    .tint(.accentColor)
                    .frame(maxWidth: 360)
            }

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Helpers

    private var progress: Double {
        Double(max(pipeline.currentStep.rawValue, highWaterStep)) / Double(GenerationStep.allCases.count)
    }

    private var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
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
