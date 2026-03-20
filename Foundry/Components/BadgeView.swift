import SwiftUI

// MARK: - Badge View

/// Capsule-shaped badge for status indicators and format labels.
struct BadgeView: View {
    let text: String
    var color: Color = .secondary
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: .capsule)
    }
}

// MARK: - Format Badge

/// Badge specifically for plugin format display (AU, VST3).
struct FormatBadge: View {
    let format: PluginFormat
    var style: BadgeStyle = .success

    enum BadgeStyle {
        case success
        case accent
        case muted

        var color: Color {
            switch self {
            case .success: .green
            case .accent: .accentColor
            case .muted: .secondary
            }
        }
    }

    var body: some View {
        BadgeView(
            text: format.rawValue,
            color: style.color,
            icon: style == .success ? "checkmark.circle.fill" : nil
        )
        .font(.subheadline)
    }
}
