import SwiftUI

// MARK: - Color Extension (Hex)

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Design Tokens

enum FoundryTheme {

    // MARK: Colors

    enum Colors {
        static let background = Color(.windowBackgroundColor)
        static let backgroundDeep = Color(.controlBackgroundColor)
        static let backgroundCard = Color(.controlBackgroundColor)
        static let backgroundElevated = Color(.underPageBackgroundColor)
        static let backgroundToolbar = Color(.windowBackgroundColor)
        static let backgroundSubtle = Color(.controlBackgroundColor)

        static let border = Color(.separatorColor)
        static let borderSubtle = Color(.tertiaryLabelColor).opacity(0.3)

        static let textPrimary = Color(.labelColor)
        static let textSecondary = Color(.secondaryLabelColor)
        static let textMuted = Color(.tertiaryLabelColor)
        static let textDimmed = Color(.quaternaryLabelColor)
        static let textFaint = Color(.quaternaryLabelColor).opacity(0.6)

        static let trafficRed = Color.red
        static let trafficYellow = Color.yellow
        static let trafficGreen = Color.green
    }

    // MARK: Fonts

    enum Fonts {
        // Architype Stedelijk — display/titles only
        static func spaceGrotesk(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .custom("ArchitypeStedelijkW00", size: size).weight(weight)
        }

        // Azeret Mono — everything else
        static func azeretMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom("Azeret Mono", size: size).weight(weight)
        }

        // Aliases kept for call-site compatibility
        static func jetBrainsMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            azeretMono(size, weight: weight)
        }

        static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            azeretMono(size, weight: weight)
        }
    }

    // MARK: Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: Layout

    enum Layout {
        static let headerHeight: CGFloat = 56
        static let statusBarHeight: CGFloat = 32
        static let borderWidth: CGFloat = 1
    }
}
