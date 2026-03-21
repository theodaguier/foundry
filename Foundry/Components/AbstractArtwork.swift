import SwiftUI

// MARK: - Abstract Artwork

/// Type-based abstract artwork used in plugin cards and library grid.
struct AbstractArtwork: View {
    let pluginType: PluginType

    var body: some View {
        switch pluginType {
        case .instrument: WaveformBarsArtwork()
        case .effect: ConcentricRingsArtwork()
        case .utility: SpectrumBarsArtwork()
        }
    }
}

// MARK: - Waveform Bars (Instruments)

struct WaveformBarsArtwork: View {
    private let bars: [(height: CGFloat, opacity: Double)] = [
        (0.80, 1.0), (0.40, 0.4), (0.90, 1.0), (0.60, 0.6),
        (0.30, 0.1), (1.00, 0.8), (0.70, 0.3), (0.50, 0.9),
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Rectangle()
                        .fill(Color.primary.opacity(bar.opacity))
                        .frame(width: 3, height: geo.size.height * bar.height * 0.85)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .overlay(
            LinearGradient(
                colors: [Color.clear.opacity(0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        )
    }
}

// MARK: - Concentric Rings (Effects)

struct ConcentricRingsArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(FoundryTheme.Colors.borderSubtle, lineWidth: 1)
                .frame(width: 96, height: 96)
            Circle()
                .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
                .frame(width: 64, height: 64)
            Circle()
                .strokeBorder(FoundryTheme.Colors.textSecondary.opacity(0.4), lineWidth: 1)
                .frame(width: 32, height: 32)
        }
    }
}

// MARK: - Spectrum Bars (Utilities)

struct SpectrumBarsArtwork: View {
    private let bars: [(width: CGFloat, opacity: Double)] = [
        (0.30, 0.3), (0.50, 0.3), (0.80, 0.3), (0.40, 0.3), (0.90, 0.3),
    ]

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        Rectangle()
                            .fill(FoundryTheme.Colors.textSecondary.opacity(bar.opacity))
                            .frame(
                                width: geo.size.width * bar.width / CGFloat(bars.count),
                                height: geo.size.height * bar.width * 0.5
                            )
                    }
                }
                .frame(height: 48)
                Rectangle()
                    .fill(FoundryTheme.Colors.borderSubtle)
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
