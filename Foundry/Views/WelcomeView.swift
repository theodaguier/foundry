import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            welcomeHeader
            Spacer()
            mainContent
            Spacer()
            welcomeFooter
        }
        .background(FoundryTheme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
    }

    // MARK: - Header

    private var welcomeHeader: some View {
        WindowChromeBar(title: "FOUNDRY", height: 48)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            Text("THIS IS WHAT FOUNDRY BUILDS.")
                .font(FoundryTheme.Fonts.azeretMono(10))
                .tracking(4)
                .foregroundStyle(Color(hex: 0x71717A))
                .textCase(.uppercase)
                .padding(.bottom, 40)

            pluginShowcaseCard
                .frame(width: 800, height: 214)

            Text("Generated from: shimmer reverb with pitch-shifted tails and freeze")
                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                .foregroundStyle(Color(hex: 0x52525B))
                .padding(.top, FoundryTheme.Spacing.xl)

            FoundryActionButton(title: "BUILD YOUR FIRST PLUGIN →") {
                appState.push(.prompt)
            }
            .padding(.top, FoundryTheme.Spacing.xxxl)
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
        .padding(.vertical, 118)
    }

    // MARK: - Plugin Showcase Card

    private var pluginShowcaseCard: some View {
        HStack(spacing: 0) {
            artworkSection
                .frame(width: 480)
            metadataSection
                .frame(width: 320)
        }
    }

    private var artworkSection: some View {
        ZStack {
            Color(hex: 0x18181B)

            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radii: [(CGFloat, CGFloat)] = [
                    (300, 0.04), (260, 0.04), (220, 0.05),
                    (180, 0.06), (140, 0.07), (100, 0.08),
                    (60, 0.1), (30, 0.12),
                ]
                for (r, opacity) in radii {
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    ctx.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(opacity)),
                        lineWidth: 1
                    )
                }
            }
            .opacity(0.2)

            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 1).frame(width: 192, height: 192)
                Circle().stroke(Color.white.opacity(0.4), lineWidth: 1).frame(width: 160, height: 160)
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 1).frame(width: 128, height: 128)
                Circle().fill(Color.white).frame(width: 16, height: 16)
            }
        }
        .clipped()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xxs) {
                Text("EFFECT · VST3 / AU")
                    .font(FoundryTheme.Fonts.jetBrainsMono(10))
                    .tracking(1)
                    .foregroundStyle(Color(hex: 0x71717A))
                    .textCase(.uppercase)

                Text("NEURAL_REVERB")
                    .font(FoundryTheme.Fonts.spaceGrotesk(36))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer()

            VStack(alignment: .leading, spacing: FoundryTheme.Spacing.lg) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: FoundryTheme.Spacing.md) {
                    MetaAttribute(label: "Algorithm", value: "PITCH_SHIFT_FREEZE")
                    MetaAttribute(label: "Architecture", value: "NEURAL_NET_V2")
                }
            }
        }
        .padding(.leading, 49)
        .padding(.trailing, FoundryTheme.Spacing.xxl)
        .padding(.vertical, FoundryTheme.Spacing.xxl)
        .background(Color(hex: 0x09090B))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
    }

    // MARK: - Footer

    private var welcomeFooter: some View {
        HStack {
            Text("© 2026 FOUNDRY SYSTEMS")
                .font(FoundryTheme.Fonts.jetBrainsMono(9))
                .tracking(0.9)
                .foregroundStyle(Color(hex: 0x3F3F46))

            Spacer()

            Text("SYST_OK // READY")
                .font(FoundryTheme.Fonts.jetBrainsMono(9))
                .tracking(0.9)
                .foregroundStyle(Color(hex: 0x3F3F46))
                .textCase(.uppercase)
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
        .padding(.vertical, FoundryTheme.Spacing.lg)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }
}

// MARK: - Meta Attribute

/// Label/value pair used in metadata sections.
struct MetaAttribute: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xxs) {
            Text(label)
                .font(FoundryTheme.Fonts.jetBrainsMono(9))
                .foregroundStyle(Color(hex: 0x52525B))
                .textCase(.uppercase)

            Text(value)
                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                .foregroundStyle(Color(hex: 0xD4D4D8))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    WelcomeView()
        .environment(AppState())
        .preferredColorScheme(.dark)
        .frame(width: 1024, height: 768)
}
