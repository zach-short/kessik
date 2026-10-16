import SwiftTerm

/// The terminal cursor shape picked in Settings. Blink is a separate setting. The defaults, a
/// blinking block, are SwiftTerm's own default. A program can still change the cursor with an
/// escape sequence (DECSCUSR).
enum CursorShape: String, CaseIterable, Identifiable {
    case block, bar, underline

    static let defaultBlink = true

    var id: String { rawValue }

    var label: String {
        switch self {
        case .block: "Block"
        case .bar: "Bar"
        case .underline: "Underline"
        }
    }

    /// SwiftTerm's style for the stored shape and blink setting. An unknown shape is a block.
    static func style(stored: String, blink: Bool) -> CursorStyle {
        (CursorShape(rawValue: stored) ?? .block).style(blink: blink)
    }

    func style(blink: Bool) -> CursorStyle {
        switch self {
        case .block: blink ? .blinkBlock : .steadyBlock
        case .bar: blink ? .blinkBar : .steadyBar
        case .underline: blink ? .blinkUnderline : .steadyUnderline
        }
    }
}
