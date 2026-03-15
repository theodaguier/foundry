import SwiftUI

enum PluginDetailAction {
    case delete
    case rename
    case regenerate
    case showInFinder
}

struct PluginDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let pluginID: UUID
    private let fallbackPlugin: Plugin
    var onAction: ((PluginDetailAction) -> Void)?

    @State private var logoProgress: PluginLogoProgress?
    @State private var logoTask: Task<Void, Never>?
    @State private var logoError: String?
    @State private var successMessage: String?

    init(plugin: Plugin, onAction: ((PluginDetailAction) -> Void)? = nil) {
        self.pluginID = plugin.id
        self.fallbackPlugin = plugin
        self.onAction = onAction
    }

    private var plugin: Plugin {
        appState.plugins.first(where: { $0.id == pluginID }) ?? fallbackPlugin
    }

    private var isGeneratingLogo: Bool {
        logoTask != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [iconColor.opacity(0.2), iconColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                VStack(spacing: 10) {
                    PluginArtworkView(
                        plugin: plugin,
                        size: 56,
                        cornerRadius: 16,
                        symbolSize: 20
                    )

                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }

            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    Text(plugin.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: .capsule)

                    if plugin.status == .failed {
                        Text("Failed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.1), in: .capsule)
                    } else {
                        Text("Installed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1), in: .capsule)
                    }
                }

                VStack(spacing: 0) {
                    infoRow("Prompt", value: plugin.prompt)
                    Divider().padding(.leading, 80)
                    infoRow("Formats", value: plugin.formats.map(\.rawValue).joined(separator: ", "))
                    Divider().padding(.leading, 80)
                    infoRow("Created", value: plugin.createdAt.formatted(date: .long, time: .shortened))

                    if let au = plugin.installPaths.au {
                        Divider().padding(.leading, 80)
                        infoRow("AU Path", value: au)
                    }
                    if let vst3 = plugin.installPaths.vst3 {
                        Divider().padding(.leading, 80)
                        infoRow("VST3 Path", value: vst3)
                    }
                }
                .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        startLogoGeneration()
                    } label: {
                        Label("Recreate Logo", systemImage: "photo.badge.sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGeneratingLogo)

                    if let successMessage {
                        Text(successMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        actionButton("Finder", icon: "folder") {
                            onAction?(.showInFinder)
                        }

                        actionButton("Rename", icon: "pencil") {
                            onAction?(.rename)
                        }

                        actionButton("Regenerate", icon: "arrow.counterclockwise") {
                            onAction?(.regenerate)
                        }

                        actionButton("Delete", icon: "trash", role: .destructive) {
                            onAction?(.delete)
                        }
                    }
                }
            }
            .padding(24)

            Spacer(minLength: 0)
        }
        .frame(width: 460, height: 560)
        .overlay {
            if let logoProgress {
                progressOverlay(for: logoProgress)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .disabled(isGeneratingLogo)
            }
        }
        .onDisappear {
            logoTask?.cancel()
        }
        .alert("Logo generation failed", isPresented: Binding(
            get: { logoError != nil },
            set: { if !$0 { logoError = nil } }
        )) {
            Button("OK") {
                logoError = nil
            }
        } message: {
            Text(logoError ?? "")
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func actionButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : nil)
    }

    @ViewBuilder
    private func progressOverlay(for progress: PluginLogoProgress) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)

                Text(progressTitle(for: progress))
                    .font(.headline)

                Text(progress.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Cancel") {
                    logoTask?.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func progressTitle(for progress: PluginLogoProgress) -> String {
        switch progress {
        case .preparing:
            "Preparing"
        case .generating:
            "Generating Logo"
        case .writing:
            "Saving Logo"
        }
    }

    private func startLogoGeneration() {
        guard logoTask == nil else { return }

        successMessage = nil
        let currentPlugin = plugin
        logoProgress = .preparing("Preparing logo generation…")

        logoTask = Task {
            do {
                let updatedPlugin = try await PluginLogoService.generateLogo(for: currentPlugin) { progress in
                    Task { @MainActor in
                        logoProgress = progress
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    PluginManager.update(updatedPlugin, in: &appState.plugins)
                    successMessage = "Logo updated"
                    logoProgress = nil
                    logoTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    logoProgress = nil
                    logoTask = nil
                }
            } catch {
                await MainActor.run {
                    logoProgress = nil
                    logoTask = nil
                    logoError = error.localizedDescription
                }
            }
        }
    }

    private var iconColor: Color {
        guard plugin.iconColor.hasPrefix("#"),
              let hex = UInt(plugin.iconColor.dropFirst(), radix: 16) else {
            return .accentColor
        }
        return Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

#Preview {
    PluginDetailView(plugin: Plugin.samplePlugins[0])
        .environment({
            let state = AppState()
            state.plugins = Plugin.samplePlugins
            return state
        }())
        .preferredColorScheme(.dark)
}
