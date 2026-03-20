import SwiftUI

// MARK: - Window Chrome Bar

/// macOS-style traffic light dots with optional centered title.
struct WindowChromeBar: View {
    var title: String? = nil
    var height: CGFloat = 32

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle().fill(FoundryTheme.Colors.trafficRed).frame(width: 12, height: 12)
                Circle().fill(FoundryTheme.Colors.trafficYellow).frame(width: 12, height: 12)
                Circle().fill(FoundryTheme.Colors.trafficGreen).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.horizontal, FoundryTheme.Spacing.md)

            if let title {
                Text(title)
                    .font(FoundryTheme.Fonts.jetBrainsMono(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(FoundryTheme.Colors.textMuted)
            }
        }
        .frame(height: height)
        .background(FoundryTheme.Colors.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }
}
