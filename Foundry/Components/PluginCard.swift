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
            HStack(spacing: 10) {
                // Rounded rect icon — App Store style
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        )

                    Image(systemName: plugin.type.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }

                // Name + subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(plugin.name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(plugin.type.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Action badge — App Store "Get" style
                Text(plugin.formats.map(\.rawValue).joined(separator: " · "))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: .capsule)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    VStack(spacing: 0) {
        PluginCard(plugin: Plugin.samplePlugins[0])
        Divider().padding(.leading, 46)
        PluginCard(plugin: Plugin.samplePlugins[1])
        Divider().padding(.leading, 46)
        PluginCard(plugin: Plugin.samplePlugins[2])
    }
    .padding(.horizontal, 12)
    .frame(width: 260)
    .background(.background)
    .preferredColorScheme(.dark)
}
