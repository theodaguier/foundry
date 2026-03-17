import SwiftUI

enum PluginDetailAction {
    case delete
    case rename
    case regenerate
    case showInFinder
}

struct PluginDetailView: View {
    let plugin: Plugin
    var onAction: ((PluginDetailAction) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Colored header
            ZStack {
                LinearGradient(
                    colors: [plugin.color.opacity(0.2), plugin.color.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(plugin.color.opacity(0.25))
                            .frame(width: 52, height: 52)

                        Image(systemName: plugin.type.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(plugin.color)
                    }

                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }

            // Content
            VStack(spacing: 20) {
                // Type + status
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

                // Info rows
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

                // Actions
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
            .padding(24)

            Spacer(minLength: 0)
        }
        .frame(width: 460, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Components

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

}

#Preview {
    PluginDetailView(plugin: Plugin.samplePlugins[0])
        .preferredColorScheme(.dark)
}
