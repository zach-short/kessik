import SwiftUI

/// Dark, low-contrast surfaces with one warm accent. Raycast-inspired, not copied.
enum Theme {
    static let background = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let surface = Color.white.opacity(0.045)
    static let surfaceRaised = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.08)

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static let accent = Color(red: 1.0, green: 0.38, blue: 0.36)
    static let online = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let offline = Color.white.opacity(0.3)

    static let corner: CGFloat = 14
    static let mono = Font.system(.footnote, design: .monospaced)
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.stroke)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
