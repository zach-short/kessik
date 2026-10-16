import Foundation

extension TerminalPalette {
    /// The built-in palettes, then the imported ones. Built-ins come first, so they win a lookup.
    static func available(defaults: UserDefaults = .standard) -> [TerminalPalette] {
        all + CustomPalettes(defaults: defaults).palettes
    }

    /// The palette a Mac's terminal draws with. The Mac's own palette wins while it still exists.
    /// When it does not, as after its imported palette is deleted, the palette from Settings is
    /// used, and Default when that one is gone too.
    static func resolve(host: Host?, global: String, available: [TerminalPalette]) -> TerminalPalette {
        if let id = host?.paletteID, let own = available.first(where: { $0.id == id }) { return own }
        return available.first { $0.id == global } ?? .standard
    }
}
