import SwiftUI

// MARK: - Corner Bracket

/// L-shaped bracket placed at corners of text fields and containers.
struct CornerBracket: Shape {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    let corner: Corner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch corner {
        case .topLeading:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topTrailing:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading:
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        case .bottomTrailing:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return p
    }
}

/// Convenience modifier to apply corner brackets to all four corners.
extension View {
    func cornerBrackets(
        color: Color = FoundryTheme.Colors.textSecondary.opacity(0.3),
        size: CGFloat = 8
    ) -> some View {
        self
            .overlay(alignment: .topLeading) {
                CornerBracket(corner: .topLeading)
                    .stroke(color, lineWidth: 1)
                    .frame(width: size, height: size)
            }
            .overlay(alignment: .topTrailing) {
                CornerBracket(corner: .topTrailing)
                    .stroke(color, lineWidth: 1)
                    .frame(width: size, height: size)
            }
            .overlay(alignment: .bottomLeading) {
                CornerBracket(corner: .bottomLeading)
                    .stroke(color, lineWidth: 1)
                    .frame(width: size, height: size)
            }
            .overlay(alignment: .bottomTrailing) {
                CornerBracket(corner: .bottomTrailing)
                    .stroke(color, lineWidth: 1)
                    .frame(width: size, height: size)
            }
    }
}

