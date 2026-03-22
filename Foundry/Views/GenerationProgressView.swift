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

    /// Labels used in refine mode — editing, not generating.
    var refineLabel: String {
        switch self {
        case .preparingProject: "Preparing project"
        case .generatingDSP: "Editing code"
        case .generatingUI: "Editing code"
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

    enum Mode: Equatable {
        case generation(GenerationConfig)
        case refinement(RefineConfig)
    }

    let mode: Mode
    @State private var showCancelConfirmation = false

    private var build: ActiveBuild? { appState.activeBuild }

    private var isRefine: Bool {
        if case .refinement = mode { return true }
        return false
    }

    private var visibleSteps: [GenerationStep] {
        isRefine
            ? [.generatingDSP, .compiling, .installing]
            : GenerationStep.allCases
    }

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
        .navigationTitle(isRefine ? "Refining" : "Building")
        .navigationBarBackButtonHidden(true)
        .toolbar {
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
        .alert(isRefine ? "Cancel Refinement?" : "Cancel Build?", isPresented: $showCancelConfirmation) {
            Button(isRefine ? "Continue" : "Continue Building", role: .cancel) {}
            Button(isRefine ? "Cancel Refinement" : "Cancel Build", role: .destructive) {
                build?.pipeline.cancel()
                build?.stopTimer()
                appState.activeBuild = nil
                appState.buildProgress = 0
                appState.popToRoot()
            }
        } message: {
            Text("This will stop the current \(isRefine ? "refinement" : "build"). You will lose all progress.")
        }
        .onAppear {
            if appState.activeBuild == nil {
                switch mode {
                case .generation(let config):
                    let newBuild = ActiveBuild(kind: .generation(config))
                    appState.activeBuild = newBuild
                    appState.buildProgress = 0
                    newBuild.pipeline.run(config: config, appState: appState)
                    newBuild.startTimer()
                case .refinement(let config):
                    let newBuild = ActiveBuild(kind: .refinement(config))
                    appState.activeBuild = newBuild
                    newBuild.pipeline.refine(config: config, appState: appState)
                    newBuild.startTimer()
                }
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

            VStack(spacing: 32) {
                // Plugin name scramble reveal
                if !isRefine {
                    NameScrambleView(
                        targetName: build?.pipeline.generatedPluginName,
                        isSearching: build?.pipeline.generatedPluginName == nil
                    )
                }

                VStack(spacing: 24) {
                    if let build {
                        GenerationStepList(
                            steps: visibleSteps,
                            currentStep: build.pipeline.currentStep,
                            completedSteps: build.completedSteps,
                            isRefine: isRefine
                        )
                        .frame(maxWidth: 360)

                        ProgressView(value: build.progress)
                            .tint(.accentColor)
                            .frame(maxWidth: 360)

                        Button("Cancel") {
                            showCancelConfirmation = true
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
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

// MARK: - Name Scramble View

/// Displays a letter-scramble animation while the AI generates a plugin name.
/// Each letter cycles independently at its own rhythm, then locks in left-to-right when the name arrives.
struct NameScrambleView: View {
    let targetName: String?
    let isSearching: Bool

    private static let glyphs: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let scrambleLength = 7

    @State private var slots: [LetterSlot] = []
    @State private var timer: Timer?
    @State private var resolved = false

    struct LetterSlot: Identifiable {
        let id: Int
        var char: Character
        var locked: Bool = false
        /// Each slot cycles at its own pace — ticks remaining before next char swap
        var tickCooldown: Int = 0
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(slots) { slot in
                Text(String(slot.char))
                    .font(.custom("ArchitypeStedelijkW00", size: 42))
                    .foregroundStyle(slot.locked ? Color.primary : Color.primary.opacity(0.25))
                    .blur(radius: slot.locked ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.2), value: slot.locked)
                    .animation(.easeOut(duration: 0.08), value: slot.char == slot.char) // triggers on char change
            }
        }
        .frame(height: 52)
        .onAppear {
            startScrambling()
            // Name may already be available if the pipeline resolved before the view appeared
            if let name = targetName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    beginResolving(to: name)
                }
            }
        }
        .onChange(of: targetName) { _, newName in
            if let name = newName { beginResolving(to: name) }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Scramble

    private func startScrambling() {
        resolved = false
        slots = (0..<Self.scrambleLength).map { i in
            LetterSlot(
                id: i,
                char: Self.glyphs.randomElement()!,
                tickCooldown: Int.random(in: 2...6)
            )
        }

        timer?.invalidate()
        // Tick every 80ms — each letter decides independently whether to swap
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            DispatchQueue.main.async {
                guard !resolved else { return }
                for i in slots.indices where !slots[i].locked {
                    slots[i].tickCooldown -= 1
                    if slots[i].tickCooldown <= 0 {
                        slots[i].char = Self.glyphs.randomElement()!
                        // Random cooldown: some letters change fast, others linger
                        slots[i].tickCooldown = Int.random(in: 1...4)
                    }
                }
            }
        }
    }

    // MARK: - Resolve

    private func beginResolving(to name: String) {
        let target = Array(name.uppercased())

        // Resize slots to match target
        while slots.count < target.count {
            slots.append(LetterSlot(id: slots.count, char: Self.glyphs.randomElement()!, tickCooldown: Int.random(in: 1...3)))
        }
        if slots.count > target.count {
            slots = Array(slots.prefix(target.count))
        }

        // Lock each letter with a staggered delay (120ms per letter)
        for i in 0..<target.count {
            let delay = Double(i) * 0.12 + 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard i < slots.count else { return }
                slots[i].char = target[i]
                slots[i].locked = true

                if i == target.count - 1 {
                    resolved = true
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
}

// MARK: - Generation Step List

struct GenerationStepList: View {
    var steps: [GenerationStep] = GenerationStep.allCases
    let currentStep: GenerationStep
    let completedSteps: Set<Int>
    var isRefine: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(steps, id: \.self) { step in
                GenerationStepRow(
                    step: step,
                    isActive: currentStep == step || (isRefine && step == .generatingDSP && currentStep == .generatingUI),
                    isDone: completedSteps.contains(step.rawValue),
                    isRefine: isRefine
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
    var isRefine: Bool = false

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

            Text(isRefine ? step.refineLabel : step.label)
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
        GenerationProgressView(mode: .generation(GenerationConfig(prompt: "A warm analog synth with detuned oscillators")))
    }
    .environment({
        let s = AppState()
        s.plugins = Plugin.samplePlugins
        return s
    }())
    .preferredColorScheme(.dark)
}
