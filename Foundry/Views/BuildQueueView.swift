import SwiftUI

struct BuildQueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if let build = appState.activeBuild {
                ScrollView {
                    VStack(spacing: 0) {
                        buildRow(build)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("Builds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    appState.popToRoot()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hammer")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No Active Builds")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Plugins will appear here\nwhile they are being built.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Build a Plugin") {
                appState.popToRoot()
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    appState.push(.prompt)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Build Row

    private func buildRow(_ build: ActiveBuild) -> some View {
        Button {
            // Navigate to the generation/refine progress view
            appState.popToRoot()
            appState.push(build.route)
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Status indicator
                    VStack {
                        if build.pipeline.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(width: 20)
                    .padding(.top, 2)

                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        // Name + time
                        HStack(alignment: .firstTextBaseline) {
                            Text(build.displayName)
                                .font(FoundryTheme.Fonts.spaceGrotesk(16))
                                .tracking(0.5)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(formattedTime(build.elapsedSeconds))
                                .font(FoundryTheme.Fonts.azeretMono(11))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }

                        // Step + percentage
                        HStack(spacing: 0) {
                            Text(build.pipeline.currentStep.terminalLabel)
                                .font(FoundryTheme.Fonts.azeretMono(10))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(Int(appState.buildProgress * 100))%")
                                .font(FoundryTheme.Fonts.azeretMono(10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(FoundryTheme.Colors.borderSubtle)
                                    .frame(height: 3)

                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: geo.size.width * appState.buildProgress, height: 3)
                            }
                        }
                        .frame(height: 3)

                        // Build attempt
                        if build.pipeline.buildAttempt > 1 {
                            Text("BUILD ATTEMPT \(build.pipeline.buildAttempt)")
                                .font(FoundryTheme.Fonts.azeretMono(9))
                                .tracking(0.8)
                                .foregroundStyle(.orange)
                        }
                    }

                    // Cancel button
                    if build.pipeline.isRunning {
                        Button {
                            build.pipeline.cancel()
                            build.stopTimer()
                            appState.activeBuild = nil
                            appState.buildProgress = 0
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(FoundryTheme.Colors.borderSubtle, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                // Bottom border
                Rectangle()
                    .fill(FoundryTheme.Colors.border)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview("With Build") {
    NavigationStack {
        BuildQueueView()
    }
    .environment({
        let s = AppState()
        s.plugins = Plugin.samplePlugins
        return s
    }())
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        BuildQueueView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
