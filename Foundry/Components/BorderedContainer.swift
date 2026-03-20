import SwiftUI

// MARK: - Bordered Container

/// A dark container with a subtle border, commonly used for cards and panels.
struct BorderedContainer<Content: View>: View {
    var backgroundColor: Color
    var borderColor: Color
    @ViewBuilder let content: () -> Content

    init(
        backgroundColor: Color = FoundryTheme.Colors.backgroundDeep,
        borderColor: Color = FoundryTheme.Colors.border,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.content = content
    }

    var body: some View {
        content()
            .background(backgroundColor)
            .overlay {
                Rectangle()
                    .stroke(borderColor, lineWidth: FoundryTheme.Layout.borderWidth)
            }
    }
}

// MARK: - View Modifier

extension View {
    /// Applies the standard Foundry bordered container style.
    func foundryBorder(
        background: Color = FoundryTheme.Colors.backgroundDeep,
        border: Color = FoundryTheme.Colors.border
    ) -> some View {
        self
            .background(background)
            .overlay {
                Rectangle()
                    .stroke(border, lineWidth: FoundryTheme.Layout.borderWidth)
            }
    }
}
