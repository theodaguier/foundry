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
                PluginArtworkView(
                    plugin: plugin,
                    size: 36,
                    cornerRadius: 10,
                    symbolSize: 15
                )

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
