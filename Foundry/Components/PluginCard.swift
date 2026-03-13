import SwiftUI

struct PluginCard: View {
    let plugin: Plugin
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?
    var onShowInFinder: (() -> Void)?
    var onRename: (() -> Void)?
    var onRegenerate: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Icon header
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: plugin.type.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(iconColor)
                    }

                    Spacer()

                    // Status indicator
                    if plugin.status == .failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text(plugin.type.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                }
                .padding(.bottom, 12)

                // Name and description
                Text(plugin.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text(plugin.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                // Footer: formats + date
                HStack(spacing: 6) {
                    ForEach(plugin.formats, id: \.self) { format in
                        Text(format.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(plugin.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(14)
            .frame(height: 170)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                onShowInFinder?()
            }

            Button("Rename...", systemImage: "pencil") {
                onRename?()
            }

            Button("Regenerate", systemImage: "arrow.counterclockwise") {
                onRegenerate?()
            }

            Divider()

            Button("Delete Plugin", systemImage: "trash", role: .destructive) {
                onDelete?()
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
    HStack(spacing: 12) {
        PluginCard(plugin: Plugin.samplePlugins[0])
            .frame(width: 220)
        PluginCard(plugin: Plugin.samplePlugins[1])
            .frame(width: 220)
        PluginCard(plugin: Plugin.samplePlugins[2])
            .frame(width: 220)
    }
    .padding(24)
    .background(.background)
    .preferredColorScheme(.dark)
}
