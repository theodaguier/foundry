import SwiftUI

// MARK: - Foundry Status Bar

/// Reusable bottom status bar displayed across main screens.
struct FoundryStatusBar: View {
    let pluginCount: Int
    var version: String = "V1.0.4-STABLE"
    var showIndicator: Bool = true

    var body: some View {
        HStack {
            Text("\(pluginCount) PLUGINS | LATENCY: 1.2MS | CPU: 14% | DISK: 2%")
                .font(FoundryTheme.Fonts.jetBrainsMono(10))
                .tracking(1)
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .textCase(.uppercase)

            Spacer()

            HStack(spacing: FoundryTheme.Spacing.md) {
                Text(version)
                    .font(FoundryTheme.Fonts.jetBrainsMono(10))
                    .tracking(1)
                    .foregroundStyle(FoundryTheme.Colors.textSecondary)
                    .textCase(.uppercase)

                if showIndicator {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.lg)
        .padding(.top, 1)
        .frame(height: FoundryTheme.Layout.statusBarHeight)
        .background(FoundryTheme.Colors.backgroundCard)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FoundryTheme.Colors.border)
                .frame(height: FoundryTheme.Layout.borderWidth)
        }
    }
}
