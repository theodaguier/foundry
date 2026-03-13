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
            // Header
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Content
            VStack(spacing: 24) {
                // Icon + name
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: plugin.type.systemImage)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(iconColor)
                    }

                    Text(plugin.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(plugin.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                }

                // Info rows
                VStack(spacing: 1) {
                    infoRow("Prompt", value: plugin.prompt)
                    infoRow("Formats", value: plugin.formats.map(\.rawValue).joined(separator: ", "))
                    infoRow("Created", value: plugin.createdAt.formatted(date: .long, time: .shortened))
                    infoRow("Status", value: plugin.status.rawValue.capitalized)

                    if let au = plugin.installPaths.au {
                        infoRow("AU Path", value: au)
                    }
                    if let vst3 = plugin.installPaths.vst3 {
                        infoRow("VST3 Path", value: vst3)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

                // Actions
                HStack(spacing: 10) {
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
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
        .frame(width: 460, height: 520)
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
        .background(.quaternary.opacity(0.3))
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
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
        .preferredColorScheme(.dark)
}
