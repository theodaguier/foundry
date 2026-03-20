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

    var body: some View {
        VStack(spacing: 0) {
            WindowChromeBar(title: "FOUNDRY CORE V1.0.4")
            topNav
            mainContent
        }
        .background(FoundryTheme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
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
            if newValue.rawValue > oldValue.rawValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = completedSteps.insert(oldValue.rawValue)
                }
            }
            appState.buildProgress = progress
        }
    }

    // MARK: - Top Nav

    private var topNav: some View {
        HStack {
            HStack(spacing: FoundryTheme.Spacing.xxl) {
                Text("FOUNDRY")
                    .font(FoundryTheme.Fonts.spaceGrotesk(20))
                    .tracking(1)
                    .foregroundStyle(.white)

                HStack(spacing: FoundryTheme.Spacing.xl) {
                    ForEach(PluginFilter.allCases, id: \.self) { tab in
                        Text(tab.rawValue)
                            .font(FoundryTheme.Fonts.jetBrainsMono(11, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(FoundryTheme.Colors.textMuted)
                    }
                }
            }

            Spacer()

            HStack(spacing: FoundryTheme.Spacing.md) {
                Text("BUILDING · \(Int(progress * 100))%")
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .foundryBorder(background: FoundryTheme.Colors.backgroundSubtle, border: Color.white.opacity(0.1))

                FoundryActionButton(title: "NEW") {
                    pipeline.cancel()
                    appState.popToRoot()
                }
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
        .frame(height: FoundryTheme.Layout.headerHeight)
        .background(FoundryTheme.Colors.background)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                leftPanel
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
                    }

                TerminalView(
                    title: "CONVERGENCE_LOG_V1.0.4.SH",
                    logLines: pipeline.logLines,
                    elapsedTime: formattedTime
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: geo.size.height)
        }
        .background(FoundryTheme.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        ZStack(alignment: .center) {
            Button {
                pipeline.cancel()
                appState.popToRoot()
            } label: {
                HStack(spacing: FoundryTheme.Spacing.xs) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                    Text("CANCEL")
                        .font(FoundryTheme.Fonts.jetBrainsMono(10))
                        .tracking(3)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 40)
            .padding(.leading, 40)

            VStack(spacing: 0) {
                radialArc
                    .padding(.bottom, FoundryTheme.Spacing.xxl)

                GenerationStepList(
                    currentStep: pipeline.currentStep,
                    completedSteps: completedSteps
                )

                Button {
                    pipeline.cancel()
                    appState.popToRoot()
                } label: {
                    Text("BACK TO LIBRARY")
                        .font(FoundryTheme.Fonts.jetBrainsMono(10))
                        .tracking(3)
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, FoundryTheme.Spacing.xxxl)
            }
            .frame(maxWidth: 448)
            .padding(.horizontal, FoundryTheme.Spacing.xxl)
        }
    }

    // MARK: - Radial Arc

    private var radialArc: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: 320, height: 320)

                SemiArc(progress: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 320, height: 320)
            }
            .frame(width: 320, height: 320)
            .frame(width: 320, height: 160, alignment: .top)
            .clipped()

            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%")
                    .font(FoundryTheme.Fonts.spaceGrotesk(60))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text("ENGINE CONVERGENCE")
                    .font(FoundryTheme.Fonts.jetBrainsMono(10))
                    .tracking(3)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
                    .padding(.top, FoundryTheme.Spacing.xs)
            }
        }
        .frame(width: 320)
    }


    // MARK: - Helpers

    private var progress: Double {
        Double(pipeline.currentStep.rawValue) / Double(GenerationStep.allCases.count)
    }

    private var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Generation Step List

/// Step list specifically styled for the generation progress panel.
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
                .padding(.top, step == .preparingProject ? 0 : FoundryTheme.Spacing.md)
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
        if isActive {
            activeRow
        } else {
            inactiveRow
        }
    }

    private var activeRow: some View {
        HStack {
            HStack(spacing: FoundryTheme.Spacing.md) {
                Image(systemName: "arrow.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 15)

                Text(step.terminalLabel)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach([1.0, 0.4, 0.1], id: \.self) { opacity in
                    Rectangle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, FoundryTheme.Spacing.md)
        .padding(.vertical, FoundryTheme.Spacing.md)
        .background(FoundryTheme.Colors.backgroundSubtle)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white).frame(width: 2)
        }
    }

    private var inactiveRow: some View {
        HStack {
            HStack(spacing: FoundryTheme.Spacing.md) {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FoundryTheme.Colors.textMuted)
                        .frame(width: 15)
                } else {
                    Circle()
                        .stroke(FoundryTheme.Colors.textFaint, lineWidth: 1)
                        .frame(width: 14, height: 14)
                        .frame(width: 15)
                }

                Text(step.terminalLabel)
                    .font(FoundryTheme.Fonts.jetBrainsMono(11))
                    .tracking(0.55)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }

            Spacer()

            if isDone {
                Text("DONE")
                    .font(FoundryTheme.Fonts.jetBrainsMono(10))
                    .foregroundStyle(FoundryTheme.Colors.textMuted.opacity(0.4))
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.xs)
        .opacity(isPending ? 0.3 : 1)
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
