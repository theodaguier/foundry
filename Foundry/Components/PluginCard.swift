import SwiftUI

struct PluginCard: View {
    let plugin: Plugin
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: plugin.type == .synth ? "pianokeys" : "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)

                Spacer()

                Text(plugin.type.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(plugin.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(plugin.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(plugin.formats, id: \.self) { format in
                    Text(format.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(plugin.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(14)
        .frame(height: 160)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        .onHover { hovering in
            isHovered = hovering
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
    }
    .padding(24)
    .background(.background)
    .preferredColorScheme(.dark)
}
