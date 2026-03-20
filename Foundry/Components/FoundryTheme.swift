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
        static let background = Color.black
        static let backgroundDeep = Color(hex: 0x0A0A0A)
        static let backgroundCard = Color(hex: 0x0E0E0E)
        static let backgroundElevated = Color(hex: 0x131313)
        static let backgroundToolbar = Color(hex: 0x1B1B1B)
        static let backgroundSubtle = Color(hex: 0x1A1A1A)

        static let border = Color(hex: 0x333333)
        static let borderSubtle = Color(hex: 0x474747)

        static let textPrimary = Color.white
        static let textSecondary = Color(hex: 0x919191)
        static let textMuted = Color(hex: 0x666666)
        static let textDimmed = Color(hex: 0x555555)
        static let textFaint = Color(hex: 0x444444)

        static let trafficRed = Color(hex: 0xFF5F56)
        static let trafficYellow = Color(hex: 0xFFBD2E)
        static let trafficGreen = Color(hex: 0x27C93F)
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
