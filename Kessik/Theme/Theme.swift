import SwiftUI
import UIKit

/// Low-contrast surfaces with one warm accent. Raycast-inspired, not copied.
/// Each color has a dark and a light value. The UIKit `ui*` values resolve per trait, so a
/// view that reads them follows the theme in use without a rebuild.
enum Theme {
    static let uiBackground = adaptive(light: gray(0.965), dark: rgb(0.047, 0.047, 0.055))
    static let background = Color(uiColor: uiBackground)
    static let surface = Color(uiColor: adaptive(light: black(0.04), dark: white(0.045)))
    static let uiSurfaceRaised = adaptive(light: black(0.07), dark: white(0.08))
    static let surfaceRaised = Color(uiColor: uiSurfaceRaised)
    static let stroke = Color(uiColor: adaptive(light: black(0.1), dark: white(0.08)))

    static let uiTextPrimary = adaptive(light: black(0.9), dark: white(0.94))
    static let textPrimary = Color(uiColor: uiTextPrimary)
    static let textSecondary = Color(uiColor: adaptive(light: black(0.56), dark: white(0.55)))
    static let textTertiary = Color(uiColor: adaptive(light: black(0.38), dark: white(0.35)))

    /// Text in the terminal. A little softer than `uiTextPrimary`, as on the dark theme.
    static let uiTerminalText = adaptive(light: gray(0.1), dark: gray(0.92))

    static let uiAccent = adaptive(light: rgb(0.85, 0.25, 0.23), dark: rgb(1.0, 0.38, 0.36))
    static let accent = Color(uiColor: uiAccent)
    static let online = Color(uiColor: adaptive(light: rgb(0.1, 0.6, 0.32), dark: rgb(0.24, 0.86, 0.52)))
    static let warning = Color(uiColor: adaptive(light: rgb(0.8, 0.5, 0.0), dark: rgb(1.0, 0.76, 0.28)))
    static let offline = Color(uiColor: adaptive(light: black(0.3), dark: white(0.3)))

    static let corner: CGFloat = 14
    /// Hostnames, paths and other short mono labels, in the font picked in Settings.
    static var mono: Font { MonoFont.current.font(.footnote) }

    /// Picks `light` or `dark` from the trait collection in use.
    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private static func gray(_ value: CGFloat) -> UIColor { UIColor(white: value, alpha: 1) }
    private static func white(_ alpha: CGFloat) -> UIColor { UIColor(white: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> UIColor { UIColor(white: 0, alpha: alpha) }
}

/// The app theme, set in Settings. `system` follows iOS. The default is dark, as before the
/// light theme existed.
enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    /// Nil lets iOS decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
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
