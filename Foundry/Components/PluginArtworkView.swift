import AppKit
import SwiftUI

struct PluginArtworkView: View {
    let plugin: Plugin
    var size: CGFloat
    var cornerRadius: CGFloat
    var symbolSize: CGFloat

    var body: some View {
        ZStack {
            if let logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: size * 0.14, y: size * 0.08)
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: plugin.type.systemImage)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var logoImage: NSImage? {
        guard let path = plugin.logoAssetPath else { return nil }
        let logoURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: logoURL.path) else { return nil }
        return NSImage(contentsOf: logoURL)
    }

    private var accentColor: Color {
        plugin.color
    }
}
